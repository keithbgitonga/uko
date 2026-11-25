import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../database/database.service';

/**
 * Persistence for the domain stores. When a database is configured, each
 * domain maps to its normalised table (migration 0004); without a database the
 * services keep their in-memory stores.
 */
@Injectable()
export class PersistenceService {
  private readonly enabled: boolean;

  constructor(config: ConfigService, private readonly db: DatabaseService) {
    this.enabled =
      (config.get<string>('persistenceStore') ??
        (config.get<string>('databaseUrl') ? 'postgres' : 'memory')) === 'postgres';
  }

  async load<T>(domain: string): Promise<Map<string, T>> {
    if (!this.enabled) return new Map<string, T>();
    switch (domain) {
      case 'booking_quote': {
        const rows = (await this.db.pool.query('SELECT * FROM quotes')).rows;
        return new Map(rows.map((r) => [r.id, this.quote(r)])) as Map<string, T>;
      }
      case 'booking_ride': {
        const rows = (await this.db.pool.query('SELECT * FROM rides')).rows;
        return new Map(rows.map((r) => [r.id, this.ride(r)])) as Map<string, T>;
      }
      case 'driver_trip': {
        const rows = (await this.db.pool.query('SELECT * FROM driver_trips')).rows;
        return new Map(rows.map((r) => [r.id, this.driverTrip(r)])) as Map<string, T>;
      }
      case 'driver_status': {
        const rows = (await this.db.pool.query('SELECT * FROM driver_availability')).rows;
        return new Map(rows.map((r) => [r.driver_id, { driverId: r.driver_id, online: r.online, updatedAt: new Date(r.updated_at).toISOString() }])) as Map<string, T>;
      }
      case 'driver_rejection': {
        const rows = (await this.db.pool.query('SELECT * FROM driver_rejections')).rows;
        return new Map(
          rows.map((r) => [`${r.driver_id}:${r.ride_id}`, { driverId: r.driver_id, rideId: r.ride_id }]),
        ) as Map<string, T>;
      }
      case 'driver_shift': {
        const rows = (await this.db.pool.query('SELECT * FROM driver_shifts')).rows;
        return new Map(
          rows.map((r) => [
            r.id,
            {
              id: r.id,
              driverId: r.driver_id,
              startedAt: new Date(r.started_at).toISOString(),
              ...(r.ended_at ? { endedAt: new Date(r.ended_at).toISOString() } : {}),
              online: r.online,
            },
          ]),
        ) as Map<string, T>;
      }
      case 'payment': {
        const rows = (await this.db.pool.query('SELECT * FROM payments')).rows;
        return new Map(rows.map((r) => [r.id, this.payment(r)])) as Map<string, T>;
      }
      case 'safety_contact': {
        const rows = (await this.db.pool.query('SELECT * FROM safety_contacts')).rows;
        return new Map(rows.map((r) => [r.id, this.safetyContact(r)])) as Map<string, T>;
      }
      case 'safety_incident': {
        const rows = (await this.db.pool.query('SELECT * FROM safety_incidents')).rows;
        return new Map(rows.map((r) => [r.id, this.safetyIncident(r)])) as Map<string, T>;
      }
      case 'scheduled_ride': {
        const rows = (await this.db.pool.query('SELECT * FROM scheduled_rides')).rows;
        return new Map(rows.map((r) => [r.id, this.scheduledRide(r)])) as Map<string, T>;
      }
      case 'schedule_series': {
        const rows = (await this.db.pool.query('SELECT * FROM schedule_series')).rows;
        return new Map(rows.map((r) => [r.id, this.series(r)])) as Map<string, T>;
      }
      default:
        return new Map<string, T>();
    }
  }

  persist(domain: string, id: string, doc: any): void {
    if (!this.enabled) return;
    const j = (value: unknown) => JSON.stringify(value ?? null);
    const run = (sql: string, params: unknown[]) =>
      this.db.pool.query(sql, params).catch((err) => console.error(`persist ${domain}/${id} failed`, err.message));
    switch (domain) {
      case 'booking_quote':
        void run(
          `INSERT INTO quotes (id, rider_id, rider_phone, pickup, dropoff, distance_km, duration_min, fare, breakdown, currency, expires_at, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
           ON CONFLICT (id) DO UPDATE SET pickup=EXCLUDED.pickup, dropoff=EXCLUDED.dropoff, fare=EXCLUDED.fare,
             breakdown=EXCLUDED.breakdown, expires_at=EXCLUDED.expires_at`,
          [doc.id, doc.riderId, doc.riderPhone, j(doc.pickup), j(doc.dropoff), doc.distanceKm, doc.durationMin, doc.fare, j(doc.breakdown), doc.currency, doc.expiresAt, doc.createdAt],
        );
        return;
      case 'booking_ride':
        void run(
          `INSERT INTO rides (id, rider_id, rider_phone, quote_id, pickup, dropoff, fare, currency, payment_method, state, driver, driver_trip_id, pickup_code, events, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
           ON CONFLICT (id) DO UPDATE SET state=EXCLUDED.state, driver=EXCLUDED.driver, driver_trip_id=EXCLUDED.driver_trip_id,
             pickup_code=EXCLUDED.pickup_code, events=EXCLUDED.events`,
          [doc.id, doc.riderId, doc.riderPhone, doc.quoteId ?? null, j(doc.pickup), j(doc.dropoff), doc.fare, doc.currency, doc.paymentMethod, doc.state, doc.driver ? j(doc.driver) : null, doc.driverTripId ?? null, doc.pickupCode ?? null, j(doc.events ?? []), doc.createdAt],
        );
        return;
      case 'driver_trip':
        void run(
          `INSERT INTO driver_trips (id, ride_id, driver_id, rider_name, pickup, dropoff, fare, currency, pickup_code, state, events, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
           ON CONFLICT (id) DO UPDATE SET state=EXCLUDED.state, events=EXCLUDED.events`,
          [doc.id, doc.rideId, doc.driverId, doc.riderName, j(doc.pickup), j(doc.dropoff), doc.fare, doc.currency, doc.pickupCode, doc.state, j(doc.events ?? []), doc.createdAt],
        );
        return;
      case 'driver_status':
        void run(
          `INSERT INTO driver_availability (driver_id, online, updated_at) VALUES ($1,$2,now())
           ON CONFLICT (driver_id) DO UPDATE SET online=EXCLUDED.online, updated_at=now()`,
          [doc.driverId, doc.online],
        );
        return;
      case 'driver_rejection':
        void run('INSERT INTO driver_rejections (driver_id, ride_id) VALUES ($1,$2) ON CONFLICT DO NOTHING', [doc.driverId, doc.rideId]);
        return;
      case 'driver_shift':
        void run(
          `INSERT INTO driver_shifts (id, driver_id, started_at, ended_at, online) VALUES ($1,$2,$3,$4,$5)
           ON CONFLICT (id) DO UPDATE SET ended_at=EXCLUDED.ended_at, online=EXCLUDED.online`,
          [doc.id, doc.driverId, doc.startedAt, doc.endedAt ?? null, doc.online],
        );
        return;
      case 'payment':
        void run(
          `INSERT INTO payments (id, ride_id, rider_id, amount, currency, method, status, checkout_request_id, merchant_request_id, customer_message, receipt, created_at, updated_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
           ON CONFLICT (id) DO UPDATE SET status=EXCLUDED.status, receipt=EXCLUDED.receipt, updated_at=EXCLUDED.updated_at`,
          [doc.id, doc.rideId, doc.riderId, doc.amount, doc.currency, doc.method, doc.status, doc.checkoutRequestId ?? null, doc.merchantRequestId ?? null, doc.customerMessage ?? null, doc.receipt ?? null, doc.createdAt, doc.updatedAt],
        );
        return;
      case 'safety_contact':
        void run(
          `INSERT INTO safety_contacts (id, rider_id, name, phone, relationship, created_at) VALUES ($1,$2,$3,$4,$5,$6)
           ON CONFLICT (id) DO NOTHING`,
          [doc.id, doc.riderId, doc.name, doc.phone, doc.relationship ?? null, doc.createdAt],
        );
        return;
      case 'safety_incident':
        void run(
          `INSERT INTO safety_incidents (id, rider_id, ride_id, type, state, lat, lng, note, contacts, events, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
           ON CONFLICT (id) DO UPDATE SET state=EXCLUDED.state, events=EXCLUDED.events`,
          [doc.id, doc.riderId, doc.rideId ?? null, doc.type ?? 'SOS', doc.state, doc.lat ?? null, doc.lng ?? null, doc.note ?? null, j(doc.contacts ?? []), j(doc.events ?? []), doc.createdAt],
        );
        return;
      case 'scheduled_ride':
        void run(
          `INSERT INTO scheduled_rides (id, rider_id, rider_phone, pickup, dropoff, scheduled_at, fare, currency, payment_method, state, series_id, activated_ride_id, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
           ON CONFLICT (id) DO UPDATE SET state=EXCLUDED.state, series_id=EXCLUDED.series_id, activated_ride_id=EXCLUDED.activated_ride_id`,
          [doc.id, doc.riderId, doc.riderPhone, j(doc.pickup), j(doc.dropoff), doc.scheduledAt, doc.fare, doc.currency, doc.paymentMethod, doc.status, doc.seriesId ?? null, doc.activatedRideId ?? null, doc.createdAt],
        );
        return;
      case 'schedule_series':
        void run(
          `INSERT INTO schedule_series (id, rider_id, rider_phone, pickup, dropoff, weekdays, time_of_day, start_date, end_date, fare, currency, payment_method, state, occurrences, created_at)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
           ON CONFLICT (id) DO UPDATE SET state=EXCLUDED.state, occurrences=EXCLUDED.occurrences`,
          [doc.id, doc.riderId, doc.riderPhone, j(doc.pickup), j(doc.dropoff), doc.weekdays, doc.timeOfDay, doc.startDate, doc.endDate, doc.fare, doc.currency, doc.paymentMethod, doc.status, j(doc.occurrences ?? []), doc.createdAt],
        );
        return;
      default:
        return;
    }
  }

  remove(domain: string, id: string): void {
    if (!this.enabled) return;
    const table = domain === 'safety_contact' ? 'safety_contacts' : null;
    if (!table) return;
    void this.db.pool.query(`DELETE FROM ${table} WHERE id = $1`, [id]).catch(() => undefined);
  }

  private quote(r: any) {
    return {
      id: r.id, riderId: r.rider_id, riderPhone: r.rider_phone, pickup: r.pickup, dropoff: r.dropoff,
      distanceKm: Number(r.distance_km), durationMin: r.duration_min, fare: r.fare, breakdown: r.breakdown,
      currency: r.currency, expiresAt: Number(r.expires_at), createdAt: r.created_at,
    };
  }

  private ride(r: any) {
    return {
      id: r.id, riderId: r.rider_id, riderPhone: r.rider_phone, quoteId: r.quote_id,
      pickup: r.pickup, dropoff: r.dropoff, fare: r.fare, currency: r.currency,
      paymentMethod: r.payment_method, state: r.state,
      ...(r.driver ? { driver: r.driver } : {}),
      ...(r.driver_trip_id ? { driverTripId: r.driver_trip_id } : {}),
      ...(r.pickup_code ? { pickupCode: r.pickup_code } : {}),
      events: r.events ?? [], createdAt: r.created_at,
    };
  }

  private driverTrip(r: any) {
    return {
      id: r.id, rideId: r.ride_id, driverId: r.driver_id, riderName: r.rider_name,
      pickup: r.pickup, dropoff: r.dropoff, fare: r.fare, currency: r.currency,
      pickupCode: r.pickup_code, state: r.state, events: r.events ?? [], createdAt: r.created_at,
    };
  }

  private payment(r: any) {
    return {
      id: r.id, rideId: r.ride_id, riderId: r.rider_id, amount: r.amount, currency: r.currency,
      method: r.method, status: r.status,
      ...(r.checkout_request_id ? { checkoutRequestId: r.checkout_request_id } : {}),
      ...(r.merchant_request_id ? { merchantRequestId: r.merchant_request_id } : {}),
      ...(r.customer_message ? { customerMessage: r.customer_message } : {}),
      ...(r.receipt ? { receipt: r.receipt } : {}),
      createdAt: Number(r.created_at), updatedAt: Number(r.updated_at),
    };
  }

  private safetyContact(r: any) {
    return {
      id: r.id, riderId: r.rider_id, name: r.name, phone: r.phone,
      ...(r.relationship ? { relationship: r.relationship } : {}), createdAt: r.created_at,
    };
  }

  private safetyIncident(r: any) {
    return {
      id: r.id, riderId: r.rider_id, ...(r.ride_id ? { rideId: r.ride_id } : {}),
      type: r.type, state: r.state,
      ...(r.lat != null ? { lat: r.lat } : {}), ...(r.lng != null ? { lng: r.lng } : {}),
      ...(r.note ? { note: r.note } : {}), contacts: r.contacts ?? [], events: r.events ?? [], createdAt: r.created_at,
    };
  }

  private scheduledRide(r: any) {
    return {
      id: r.id, riderId: r.rider_id, riderPhone: r.rider_phone, pickup: r.pickup, dropoff: r.dropoff,
      scheduledAt: r.scheduled_at, fare: r.fare, currency: r.currency, paymentMethod: r.payment_method,
      status: r.state, ...(r.series_id ? { seriesId: r.series_id } : {}), ...(r.activated_ride_id ? { activatedRideId: r.activated_ride_id } : {}), createdAt: r.created_at,
    };
  }

  private series(r: any) {
    const iso = (d: unknown) => (d instanceof Date ? d.toISOString().slice(0, 10) : String(d));
    return {
      id: r.id, riderId: r.rider_id, riderPhone: r.rider_phone, pickup: r.pickup, dropoff: r.dropoff,
      weekdays: r.weekdays, timeOfDay: r.time_of_day, startDate: iso(r.start_date), endDate: iso(r.end_date),
      fare: r.fare, currency: r.currency, paymentMethod: r.payment_method, status: r.state,
      occurrences: r.occurrences ?? [], createdAt: r.created_at,
    };
  }
}
