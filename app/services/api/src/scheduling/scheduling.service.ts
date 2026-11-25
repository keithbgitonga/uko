import { BadRequestException, Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Stop } from '../booking/booking.service';
import { BookingService } from '../booking/booking.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PersistenceService } from '../persistence/persistence.service';

export interface ScheduledRide {
  id: string;
  riderId: string;
  riderPhone: string;
  pickup: Stop;
  dropoff: Stop;
  scheduledAt: string;
  fare: number;
  currency: 'KES';
  paymentMethod: 'mpesa' | 'cash';
  status: 'SCHEDULED' | 'ACTIVATED' | 'MISSED' | 'CANCELLED' | 'COMPLETED';
  seriesId?: string;
  activatedRideId?: string;
  createdAt: string;
}

export interface SeriesOccurrence {
  date: string;
  status: 'SCHEDULED' | 'ACTIVATED' | 'MISSED' | 'CANCELLED';
  rideId?: string;
}

export interface ScheduleSeries {
  id: string;
  riderId: string;
  riderPhone: string;
  pickup: Stop;
  dropoff: Stop;
  weekdays: number[];
  timeOfDay: string;
  startDate: string;
  endDate: string;
  fare: number;
  currency: 'KES';
  paymentMethod: 'mpesa' | 'cash';
  status: 'ACTIVE' | 'PAUSED' | 'CANCELLED' | 'FINISHED';
  occurrences: SeriesOccurrence[];
  createdAt: string;
}

const MIN_LEAD_MS = 45 * 60 * 1000;
const MAX_AHEAD_DAYS = 90;
const SERIES_MAX_WEEKS = 8;
const SERIES_HORIZON_DAYS = 14;
const BODA_BASE_FARE = 50;
const PER_KM = 25;
const PER_MINUTE = 3;
const MINIMUM_FARE = 80;

/**
 * In-memory scheduling store: single scheduled rides and weekly recurring
 * series. Series occurrence generation is capped at 14 days ahead per the
 * MVP design; Postgres repositories land in the database sprint.
 */
@Injectable()
export class SchedulingService implements OnModuleInit {
  private rides = new Map<string, ScheduledRide>();
  private series = new Map<string, ScheduleSeries>();

  private readonly logger = new Logger(SchedulingService.name);

  constructor(
    private readonly persistence: PersistenceService,
    private readonly booking: BookingService,
    private readonly notifications: NotificationsService,
  ) {}

  async onModuleInit(): Promise<void> {
    this.rides = await this.persistence.load<ScheduledRide>('scheduled_ride');
    this.series = await this.persistence.load<ScheduleSeries>('schedule_series');
    void this.activateDue();
    const timer = setInterval(() => void this.activateDue(), 60_000);
    timer.unref?.();
  }

  /**
   * Turns scheduled rides that are due (or just overdue) into live SEARCHING
   * rides. Runs on startup and every minute; can be forced for a dry run.
   */
  async activateDue(now = Date.now()): Promise<{ activated: unknown[]; missed: number }> {
    const leadMs = 10 * 60 * 1000;
    const missedAfterMs = 60 * 60 * 1000;
    const activated: unknown[] = [];
    let missed = 0;
    for (const ride of [...this.rides.values()]) {
      if (ride.status !== 'SCHEDULED') continue;
      const at = new Date(ride.scheduledAt).getTime();
      if (Number.isNaN(at)) continue;
      if (at > now + leadMs) continue;
      if (at < now - missedAfterMs) {
        ride.status = 'MISSED';
        this.persistence.persist('scheduled_ride', ride.id, ride);
        missed += 1;
        continue;
      }
      try {
        const quote = await this.booking.createQuote(ride.riderId, ride.riderPhone, ride.pickup, ride.dropoff);
        const live = this.booking.createRide(ride.riderId, quote.id, ride.paymentMethod);
        ride.status = 'ACTIVATED';
        ride.activatedRideId = live.id;
        this.persistence.persist('scheduled_ride', ride.id, ride);
        void this.notifications.send(
          ride.riderId,
          'Scheduled Boda is ready',
          `${ride.pickup.address} → ${ride.dropoff.address} · KES ${live.fare}. Finding a driver now.`,
          { rideId: live.id, scheduledRideId: ride.id, type: 'SCHEDULE_ACTIVATED' },
        );
        activated.push({ scheduledRideId: ride.id, rideId: live.id });
      } catch (err) {
        this.logger.error(`scheduled ride activation failed: ${err instanceof Error ? err.message : err}`);
      }
    }

    // Recurring series: keep the 14-day occurrence window rolling, then
    // activate due occurrences into live rides.
    for (const series of [...this.series.values()]) {
      if (series.status !== 'ACTIVE') continue;
      if (this.extendOccurrences(series, now)) {
        this.persistence.persist('schedule_series', series.id, series);
      }
      for (const occurrence of series.occurrences) {
        if (occurrence.status !== 'SCHEDULED') continue;
        const at = new Date(`${occurrence.date}T${series.timeOfDay}:00+03:00`).getTime();
        if (Number.isNaN(at) || at > now + leadMs) continue;
        if (at < now - missedAfterMs) {
          occurrence.status = 'MISSED';
          missed += 1;
          this.persistence.persist('schedule_series', series.id, series);
          continue;
        }
        try {
          const quote = await this.booking.createQuote(series.riderId, series.riderPhone, series.pickup, series.dropoff);
          const live = this.booking.createRide(series.riderId, quote.id, series.paymentMethod);
          occurrence.status = 'ACTIVATED';
          occurrence.rideId = live.id;
          this.persistence.persist('schedule_series', series.id, series);
          void this.notifications.send(
            series.riderId,
            'Recurring Boda is ready',
            `${series.pickup.address} → ${series.dropoff.address} · KES ${live.fare}. Finding a driver now.`,
            { rideId: live.id, seriesId: series.id, type: 'SERIES_OCCURRENCE_ACTIVATED' },
          );
          activated.push({ seriesId: series.id, occurrenceDate: occurrence.date, rideId: live.id });
        } catch (err) {
          this.logger.error(`series occurrence activation failed: ${err instanceof Error ? err.message : err}`);
        }
      }
    }
    return { activated, missed };
  }

  /** Keeps the recurring-series occurrence window topped up to 14 days ahead. */
  private extendOccurrences(series: ScheduleSeries, now: number): boolean {
    const horizon = isoDate(new Date(now + SERIES_HORIZON_DAYS * 24 * 3600 * 1000));
    const lastDate = series.occurrences.length > 0
      ? series.occurrences[series.occurrences.length - 1].date
      : series.startDate;
    const cursor = new Date(`${lastDate}T00:00:00.000Z`);
    cursor.setUTCDate(cursor.getUTCDate() + 1);
    let changed = false;
    while (isoDate(cursor) <= horizon && isoDate(cursor) <= series.endDate && series.occurrences.length < 200) {
      if (series.weekdays.includes(isoWeekday(cursor))) {
        series.occurrences.push({ date: isoDate(cursor), status: 'SCHEDULED' });
        changed = true;
      }
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    return changed;
  }

  createRide(
    riderId: string,
    riderPhone: string,
    pickup: Stop,
    dropoff: Stop,
    scheduledAt: string,
    paymentMethod: 'mpesa' | 'cash',
  ): ScheduledRide {
    const when = new Date(scheduledAt);
    if (Number.isNaN(when.getTime())) throw new BadRequestException({ code: 'SCHEDULE_INVALID_TIME' });
    const now = Date.now();
    if (when.getTime() < now + MIN_LEAD_MS) {
      throw new BadRequestException({ code: 'SCHEDULE_TOO_SOON', message: 'Schedule at least 45 minutes ahead' });
    }
    if (when.getTime() > now + MAX_AHEAD_DAYS * 24 * 3600 * 1000) {
      throw new BadRequestException({ code: 'SCHEDULE_TOO_FAR', message: 'Schedule at most 90 days ahead' });
    }

    const ride: ScheduledRide = {
      id: `sr_${randomUUID()}`,
      riderId,
      riderPhone,
      pickup,
      dropoff,
      scheduledAt: when.toISOString(),
      fare: this.price(pickup, dropoff),
      currency: 'KES',
      paymentMethod,
      status: 'SCHEDULED',
      createdAt: new Date().toISOString(),
    };
    this.rides.set(ride.id, ride);
    this.persistence.persist('scheduled_ride', ride.id, ride);
    return ride;
  }

  listRides(riderId: string): ScheduledRide[] {
    const cutoff = Date.now() - 60 * 60 * 1000;
    return [...this.rides.values()]
      .filter((r) => r.riderId === riderId && new Date(r.scheduledAt).getTime() >= cutoff)
      .sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt));
  }

  cancelRide(riderId: string, id: string): ScheduledRide {
    const ride = this.rides.get(id);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException({ code: 'SCHEDULED_RIDE_NOT_FOUND' });
    if (ride.status !== 'SCHEDULED') throw new BadRequestException({ code: 'SCHEDULED_RIDE_NOT_CANCELLABLE' });
    ride.status = 'CANCELLED';
    this.persistence.persist('scheduled_ride', ride.id, ride);
    return ride;
  }

  repeatRide(riderId: string, rideId: string, weekdays: number[], endDateInput: string): ScheduleSeries {
    const ride = this.rides.get(rideId);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException({ code: 'SCHEDULED_RIDE_NOT_FOUND' });
    if (ride.status !== 'SCHEDULED') throw new BadRequestException({ code: 'SCHEDULED_RIDE_NOT_ACTIVE' });

    const start = new Date(ride.scheduledAt);
    const startDate = nairobiDate(start);
    const end = new Date(endDateInput);
    if (Number.isNaN(end.getTime()) || end.getTime() <= start.getTime()) {
      throw new BadRequestException({ code: 'SERIES_INVALID_END' });
    }
    const maxEnd = new Date(start.getTime() + SERIES_MAX_WEEKS * 7 * 24 * 3600 * 1000);
    if (end.getTime() > maxEnd.getTime()) {
      throw new BadRequestException({ code: 'SERIES_TOO_LONG', message: 'A series can last at most 8 weeks' });
    }

    const uniqueDays = [...new Set(weekdays)].sort((a, b) => a - b);
    const occurrences: SeriesOccurrence[] = [];
    const horizon = new Date(Math.min(end.getTime(), Date.now() + SERIES_HORIZON_DAYS * 24 * 3600 * 1000));
    const cursor = new Date(`${startDate}T00:00:00.000Z`);
    const horizonDate = nairobiDate(horizon);
    while (isoDate(cursor) <= horizonDate && occurrences.length < 100) {
      if (uniqueDays.includes(isoWeekday(cursor))) {
        occurrences.push({ date: isoDate(cursor), status: 'SCHEDULED' });
      }
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }

    const series: ScheduleSeries = {
      id: `ss_${randomUUID()}`,
      riderId,
      riderPhone: ride.riderPhone,
      pickup: ride.pickup,
      dropoff: ride.dropoff,
      weekdays: uniqueDays,
      timeOfDay: nairobiTime(start),
      startDate,
      endDate: nairobiDate(end),
      fare: ride.fare,
      currency: 'KES',
      paymentMethod: ride.paymentMethod,
      status: 'ACTIVE',
      occurrences,
      createdAt: new Date().toISOString(),
    };
    this.series.set(series.id, series);
    ride.seriesId = series.id;
    this.persistence.persist('schedule_series', series.id, series);
    this.persistence.persist('scheduled_ride', ride.id, ride);
    return series;
  }

  allScheduledRides(): ScheduledRide[] {
    return [...this.rides.values()].sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt));
  }

  allSeries(): ScheduleSeries[] {
    return [...this.series.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  listSeries(riderId: string): ScheduleSeries[] {
    return [...this.series.values()]
      .filter((s) => s.riderId === riderId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  updateSeries(riderId: string, id: string, status: 'ACTIVE' | 'PAUSED' | 'CANCELLED'): ScheduleSeries {
    const series = this.series.get(id);
    if (!series || series.riderId !== riderId) throw new NotFoundException({ code: 'SERIES_NOT_FOUND' });
    if (series.status === 'CANCELLED' && status !== 'CANCELLED') {
      throw new BadRequestException({ code: 'SERIES_ALREADY_CANCELLED' });
    }
    series.status = status;
    if (status === 'CANCELLED') {
      series.occurrences = series.occurrences.map((o) => ({ ...o, status: 'CANCELLED' }));
    }
    this.persistence.persist('schedule_series', series.id, series);
    return series;
  }

  private price(pickup: Stop, dropoff: Stop): number {
    const km = Math.max(0.4, haversineKm(pickup, dropoff));
    const minutes = Math.max(4, Math.round((km / 22) * 60));
    return Math.max(MINIMUM_FARE, BODA_BASE_FARE + Math.round(km * PER_KM) + Math.round(minutes * PER_MINUTE));
  }
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function nairobiDate(d: Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(d);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function nairobiTime(d: Date): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Nairobi',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(d);
}

function isoWeekday(d: Date): number {
  return ((d.getUTCDay() + 6) % 7) + 1;
}

function haversineKm(a: Stop, b: Stop): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
