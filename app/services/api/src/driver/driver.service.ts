import { BadRequestException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomInt, randomUUID } from 'node:crypto';
import { BookingService, Ride, Stop } from '../booking/booking.service';
import { ConfigService } from '@nestjs/config';
import { DocumentsService } from '../documents/documents.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PersistenceService } from '../persistence/persistence.service';

export interface DriverOffer {
  id: string;
  rideId: string;
  driverId: string;
  riderName: string;
  pickup: Stop;
  dropoff: Stop;
  fare: number;
  currency: 'KES';
  distanceKm: number;
  durationMin: number;
  etaMin: number;
  createdAt: string;
}

export interface DriverShift {
  id: string;
  driverId: string;
  startedAt: string;
  endedAt?: string;
  online: boolean;
}

interface DriverTrip {
  id: string;
  rideId: string;
  driverId: string;
  riderName: string;
  pickup: Stop;
  dropoff: Stop;
  fare: number;
  currency: 'KES';
  pickupCode: string;
  state: 'ACCEPTED' | 'ARRIVED' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED';
  events: { at: string; state: string; note?: string }[];
  createdAt: string;
}

/**
 * Driver matching over the shared booking store. Offers are real pending
 * rider rides; accepting one assigns the driver to that ride, so both apps
 * follow the same record. Postgres-backed repositories arrive in the DB sprint.
 */
@Injectable()
export class DriverService implements OnModuleInit {
  private online = new Map<string, boolean>();
  private rejected = new Map<string, Set<string>>();
  private trips = new Map<string, DriverTrip[]>();
  private shifts = new Map<string, DriverShift>();

  constructor(
    private readonly booking: BookingService,
    private readonly persistence: PersistenceService,
    private readonly notifications: NotificationsService,
    private readonly documents: DocumentsService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    const trips = await this.persistence.load<DriverTrip>('driver_trip');
    for (const trip of trips.values()) {
      const list = this.trips.get(trip.driverId) ?? [];
      list.push(trip);
      this.trips.set(trip.driverId, list);
    }
    const states = await this.persistence.load<{ driverId: string; online: boolean; updatedAt?: string }>('driver_status');
    for (const state of states.values()) this.online.set(state.driverId, state.online);
    const rejections = await this.persistence.load<{ driverId: string; rideId: string }>('driver_rejection');
    for (const rejection of rejections.values()) {
      const set = this.rejected.get(rejection.driverId) ?? new Set<string>();
      set.add(rejection.rideId);
      this.rejected.set(rejection.driverId, set);
    }
    this.shifts = await this.persistence.load<DriverShift>('driver_shift');
    // Document gate: an online state persisted before vetting must not bypass
    // the requirement after a restart.
    if (this.config.get<boolean>('documents.required')) {
      for (const [driverId, isOnline] of [...this.online.entries()]) {
        if (isOnline && !(await this.documents.canGoOnline(driverId))) {
          this.online.set(driverId, false);
          this.persistence.persist('driver_status', driverId, { driverId, online: false });
        }
      }
    }
    // If the driver is online but no open shift survived (e.g. a restart),
    // open one from the last availability update so online time keeps counting.
    for (const [driverId, isOnline] of this.online.entries()) {
      if (!isOnline || this.openShift(driverId)) continue;
      const state = states.get(driverId);
      const shift: DriverShift = {
        id: `sh_${randomUUID()}`,
        driverId,
        startedAt: state?.updatedAt ?? new Date().toISOString(),
        online: true,
      };
      this.shifts.set(shift.id, shift);
      this.persistence.persist('driver_shift', shift.id, shift);
    }
  }

  status(driverId: string) {
    let activeTrip = this.currentTrip(driverId);
    if (activeTrip) {
      const ride = this.booking.findRideById(activeTrip.rideId);
      if (ride?.state === 'CANCELLED' && activeTrip.state !== 'CANCELLED') {
        activeTrip.state = 'CANCELLED';
        activeTrip.events.push({ at: new Date().toISOString(), state: 'CANCELLED', note: 'Rider or dispatch cancelled the ride' });
        this.persistence.persist('driver_trip', activeTrip.id, activeTrip);
      }
      if (activeTrip.state === 'CANCELLED') activeTrip = undefined;
    }
    return {
      online: this.online.get(driverId) ?? false,
      activeTrip,
      offers: activeTrip ? [] : this.offersFor(driverId),
    };
  }

  async setOnline(driverId: string, isOnline: boolean) {
    if (isOnline) await this.documents.assertCanGoOnline(driverId);
    const wasOnline = this.online.get(driverId) ?? false;
    this.online.set(driverId, isOnline);
    this.persistence.persist('driver_status', driverId, { driverId, online: isOnline });
    if (isOnline && !wasOnline) {
      const shift: DriverShift = {
        id: `sh_${randomUUID()}`,
        driverId,
        startedAt: new Date().toISOString(),
        online: true,
      };
      this.shifts.set(shift.id, shift);
      this.persistence.persist('driver_shift', shift.id, shift);
    } else if (!isOnline && wasOnline) {
      const openShift = this.openShift(driverId);
      if (openShift) {
        openShift.endedAt = new Date().toISOString();
        openShift.online = false;
        this.persistence.persist('driver_shift', openShift.id, openShift);
      }
    }
    return this.status(driverId);
  }

  shiftSummary(driverId: string) {
    const today = nairobiDate(new Date().toISOString());
    const cutoffs = todayBounds();
    let onlineMinutes = 0;
    for (const shift of this.shifts.values()) {
      if (shift.driverId !== driverId) continue;
      const started = new Date(shift.startedAt).getTime();
      const ended = shift.endedAt ? new Date(shift.endedAt).getTime() : Date.now();
      const from = Math.max(started, cutoffs.start);
      const to = Math.min(ended, cutoffs.end);
      if (to > from) onlineMinutes += Math.round((to - from) / 60000);
    }
    const earnings = this.earnings(driverId);
    const open = this.openShift(driverId);
    return {
      online: this.online.get(driverId) ?? false,
      onShiftSince: open?.startedAt,
      onlineMinutesToday: onlineMinutes,
      tripsToday: earnings.today.trips,
      grossToday: earnings.today.gross,
      commissionToday: earnings.today.commission,
      netToday: earnings.today.net,
      currency: 'KES',
      commissionPercent: earnings.commissionPercent,
    };
  }

  private openShift(driverId: string): DriverShift | undefined {
    return [...this.shifts.values()]
      .filter((s) => s.driverId === driverId && !s.endedAt)
      .sort((a, b) => b.startedAt.localeCompare(a.startedAt))[0];
  }

  offersFor(driverId: string): DriverOffer[] {
    if (!(this.online.get(driverId) ?? false)) return [];
    if (this.currentTrip(driverId)) return [];
    const rejected = this.rejected.get(driverId) ?? new Set<string>();
    return this.booking
      .pendingRides()
      .filter((ride) => !rejected.has(ride.id))
      .map((ride) => this.toOffer(driverId, ride));
  }

  acceptOffer(driverId: string, offerId: string): DriverTrip {
    if (!(this.online.get(driverId) ?? false)) throw new BadRequestException({ code: 'DRIVER_OFFLINE' });
    if (this.currentTrip(driverId)) throw new BadRequestException({ code: 'TRIP_ALREADY_ACTIVE' });
    const offer = this.offersFor(driverId).find((o) => o.id === offerId);
    if (!offer) throw new NotFoundException({ code: 'OFFER_NOT_FOUND' });
    const ride = this.booking.findRide(offer.rideId);

    const trip: DriverTrip = {
      id: `t_${randomUUID()}`,
      rideId: ride.id,
      driverId,
      riderName: offer.riderName,
      pickup: ride.pickup,
      dropoff: ride.dropoff,
      fare: ride.fare,
      currency: 'KES',
      pickupCode: String(randomInt(1000, 10000)),
      state: 'ACCEPTED',
      events: [{ at: new Date().toISOString(), state: 'ACCEPTED', note: 'Trip accepted' }],
      createdAt: new Date().toISOString(),
    };

    // Assign the driver to the rider's ride — this is the shared record.
    this.booking.assignDriver(ride.id, this.driverProfile(driverId), trip.id, trip.pickupCode);

    const trips = this.trips.get(driverId) ?? [];
    trips.push(trip);
    this.trips.set(driverId, trips);
    this.persistence.persist('driver_trip', trip.id, trip);
    void this.notifications.send(
      driverId,
      'Trip accepted',
      `${ride.pickup.address} → ${ride.dropoff.address} · KES ${ride.fare}`,
      { tripId: trip.id, rideId: ride.id, type: 'TRIP_ACCEPTED' },
    );
    return trip;
  }

  rejectOffer(driverId: string, offerId: string) {
    const offer = this.offersFor(driverId).find((o) => o.id === offerId);
    if (offer) {
      const rejected = this.rejected.get(driverId) ?? new Set<string>();
      rejected.add(offer.rideId);
      this.rejected.set(driverId, rejected);
      this.persistence.persist('driver_rejection', `${driverId}:${offer.rideId}`, { driverId, rideId: offer.rideId });
    }
    return this.status(driverId);
  }

  onlineDriverCount(): number {
    return [...this.online.entries()].filter(([, online]) => online).length;
  }

  earnings(driverId: string) {
    const completed = (this.trips.get(driverId) ?? []).filter((t) => t.state === 'COMPLETED');
    const today = nairobiDate(new Date().toISOString());
    const todayTrips = completed.filter((t) => nairobiDate(t.createdAt) === today);
    return {
      currency: 'KES' as const,
      commissionPercent: 20,
      today: this.summarize(todayTrips),
      lifetime: this.summarize(completed),
    };
  }

  private summarize(trips: DriverTrip[]) {
    const gross = trips.reduce((sum, t) => sum + t.fare, 0);
    const commission = Math.round(gross * 0.2);
    return { trips: trips.length, gross, commission, net: gross - commission };
  }

  currentTrip(driverId: string): DriverTrip | null {
    const trips = this.trips.get(driverId) ?? [];
    return [...trips].reverse().find((t) => t.state !== 'COMPLETED' && t.state !== 'CANCELLED') ?? null;
  }

  advanceTrip(driverId: string, tripId: string, action: 'arrived' | 'start' | 'complete', pickupCode?: string): DriverTrip {
    const trip = (this.trips.get(driverId) ?? []).find((t) => t.id === tripId);
    if (!trip) throw new NotFoundException({ code: 'TRIP_NOT_FOUND' });
    if (action === 'arrived' && trip.state === 'ACCEPTED') {
      trip.state = 'ARRIVED';
      trip.events.push({ at: new Date().toISOString(), state: 'ARRIVED', note: 'Driver arrived at pickup' });
      this.booking.updateRideForDriver(trip.rideId, 'ARRIVED');
    } else if (action === 'start' && trip.state === 'ARRIVED') {
      if (!pickupCode) {
        throw new BadRequestException({ code: 'PICKUP_CODE_REQUIRED', message: 'Enter the rider pickup code before starting the trip.' });
      }
      if (pickupCode !== trip.pickupCode) {
        throw new BadRequestException({ code: 'PICKUP_CODE_INVALID', message: 'That pickup code does not match the rider. Ask the rider to confirm it.' });
      }
      trip.state = 'IN_PROGRESS';
      trip.events.push({ at: new Date().toISOString(), state: 'IN_PROGRESS', note: 'Trip started' });
      this.booking.updateRideForDriver(trip.rideId, 'IN_PROGRESS');
    } else if (action === 'complete' && trip.state === 'IN_PROGRESS') {
      trip.state = 'COMPLETED';
      trip.events.push({ at: new Date().toISOString(), state: 'COMPLETED', note: 'Trip completed' });
      this.booking.updateRideForDriver(trip.rideId, 'COMPLETED');
    } else {
      throw new BadRequestException({ code: 'INVALID_TRIP_TRANSITION', message: `Cannot ${action} from ${trip.state}` });
    }
    this.persistence.persist('driver_trip', trip.id, trip);
    const fare = trip.fare;
    const messages: Record<string, { title: string; body: string }> = {
      ARRIVED: { title: 'At pickup', body: 'Rider has been notified. Ask the rider for their pickup code before starting.' },
      IN_PROGRESS: { title: 'Trip started', body: `${trip.pickup.address} → ${trip.dropoff.address}` },
      COMPLETED: { title: 'Trip completed', body: `Net KES ${Math.round(fare * 0.8)} after commission. Nice work.` },
    };
    const message = messages[action.toUpperCase() === 'ARRIVED' ? 'ARRIVED' : action === 'start' ? 'IN_PROGRESS' : 'COMPLETED'];
    if (message) void this.notifications.send(driverId, message.title, message.body, { tripId: trip.id, type: action });
    return trip;
  }

  private toOffer(driverId: string, ride: Ride): DriverOffer {
    const km = haversineKm(ride.pickup, ride.dropoff);
    return {
      id: `o_${ride.id}`,
      rideId: ride.id,
      driverId,
      riderName: `Rider ${ride.riderPhone.slice(-4)}`,
      pickup: ride.pickup,
      dropoff: ride.dropoff,
      fare: ride.fare,
      currency: 'KES',
      distanceKm: Number(km.toFixed(1)),
      durationMin: Math.max(4, Math.round((km / 22) * 60)),
      etaMin: 2,
      createdAt: ride.createdAt,
    };
  }

  private driverProfile(driverId: string) {
    return {
      driverId,
      name: 'Peter M.',
      vehicle: 'Bajaj Boxer',
      plate: 'KDA 123A',
      rating: 4.9,
      etaMin: 2,
      phoneMasked: '+2547****001',
    };
  }
}

function todayBounds(): { start: number; end: number } {
  const now = new Date();
  const date = nairobiDate(now.toISOString());
  const start = new Date(`${date}T00:00:00+03:00`).getTime();
  return { start, end: start + 24 * 3600 * 1000 };
}

function nairobiDate(iso: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}`;
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
