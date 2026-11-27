import { BadRequestException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { NotificationsService } from '../notifications/notifications.service';
import { RoutesService } from '../routes/routes.service';
import { AnalyticsService } from '../observability/analytics.service';
import { PersistenceService } from '../persistence/persistence.service';

export interface Stop {
  lat: number;
  lng: number;
  address: string;
}

export type RideState =
  | 'SEARCHING'
  | 'ASSIGNED'
  | 'ARRIVING'
  | 'ARRIVED'
  | 'IN_PROGRESS'
  | 'COMPLETED'
  | 'CANCELLED';

export interface Quote {
  id: string;
  riderId: string;
  riderPhone: string;
  pickup: Stop;
  dropoff: Stop;
  distanceKm: number;
  durationMin: number;
  fare: number;
  breakdown: { baseFare: number; distanceFare: number; timeFare: number; minimumFareApplied: boolean };
  currency: 'KES';
  expiresAt: number;
  createdAt: string;
}

export interface AssignedDriver {
  driverId?: string;
  name: string;
  vehicle: string;
  plate: string;
  rating: number;
  etaMin: number;
  phoneMasked: string;
}

export interface RideEvent {
  at: string;
  state: string;
  note?: string;
}

export interface Ride {
  id: string;
  riderId: string;
  riderPhone: string;
  quoteId: string;
  pickup: Stop;
  dropoff: Stop;
  fare: number;
  currency: 'KES';
  paymentMethod: 'mpesa' | 'cash';
  state: RideState;
  driver?: AssignedDriver;
  driverTripId?: string;
  pickupCode?: string;
  cancellation?: {
    code: string;
    label: string;
    note?: string;
    by: 'rider' | 'driver' | 'dispatch' | 'system';
    at: string;
  };
  events: RideEvent[];
  createdAt: string;
}

const BODA_BASE_FARE = 50;
const PER_KM = 25;
const PER_MINUTE = 3;
const MINIMUM_FARE = 80;
const AVG_SPEED_KMH = 22;
const PENDING_WINDOW_MS = 10 * 60 * 1000;

/**
 * In-memory booking store for the walking skeleton. Driver matching calls
 * assignDriver when a driver accepts an offer; rider and driver now share one
 * ride record. Replaced by Postgres repositories in the database sprint.
 */
@Injectable()
export class BookingService implements OnModuleInit {
  private quotes = new Map<string, Quote>();
  private rides = new Map<string, Ride>();

  constructor(
    private readonly persistence: PersistenceService,
    private readonly notifications: NotificationsService,
    private readonly routes: RoutesService,
    private readonly analytics: AnalyticsService,
  ) {}

  async onModuleInit(): Promise<void> {
    this.quotes = await this.persistence.load<Quote>('booking_quote');
    this.rides = await this.persistence.load<Ride>('booking_ride');
  }

  async createQuote(riderId: string, riderPhone: string, pickup: Stop, dropoff: Stop): Promise<Quote> {
    let distanceKm: number;
    let durationMin: number;
    try {
      const route = await this.routes.route(pickup.lat, pickup.lng, dropoff.lat, dropoff.lng);
      distanceKm = Math.max(0.4, route.distanceKm);
      durationMin = Math.max(4, route.durationMin);
    } catch {
      distanceKm = Math.max(0.4, haversineKm(pickup, dropoff));
      durationMin = Math.max(4, Math.round((distanceKm / AVG_SPEED_KMH) * 60));
    }
    const distanceFare = Math.round(distanceKm * PER_KM);
    const timeFare = Math.round(durationMin * PER_MINUTE);
    const rawFare = BODA_BASE_FARE + distanceFare + timeFare;
    const fare = Math.max(MINIMUM_FARE, rawFare);

    const quote: Quote = {
      id: `q_${randomUUID()}`,
      riderId,
      riderPhone,
      pickup,
      dropoff,
      distanceKm: Number(distanceKm.toFixed(2)),
      durationMin,
      fare,
      breakdown: {
        baseFare: BODA_BASE_FARE,
        distanceFare,
        timeFare,
        minimumFareApplied: rawFare < MINIMUM_FARE,
      },
      currency: 'KES',
      expiresAt: Date.now() + 5 * 60 * 1000,
      createdAt: new Date().toISOString(),
    };
    this.quotes.set(quote.id, quote);
    this.persistence.persist('booking_quote', quote.id, quote);
    return quote;
  }

  createRide(riderId: string, quoteId: string, paymentMethod: 'mpesa' | 'cash'): Ride {
    const quote = this.quotes.get(quoteId);
    if (!quote) throw new NotFoundException({ code: 'QUOTE_NOT_FOUND' });
    if (quote.riderId !== riderId) throw new BadRequestException({ code: 'QUOTE_NOT_OWNED' });
    if (Date.now() > quote.expiresAt) throw new BadRequestException({ code: 'QUOTE_EXPIRED' });

    const ride: Ride = {
      id: `r_${randomUUID()}`,
      riderId,
      riderPhone: quote.riderPhone,
      quoteId,
      pickup: quote.pickup,
      dropoff: quote.dropoff,
      fare: quote.fare,
      currency: 'KES',
      paymentMethod,
      state: 'SEARCHING',
      events: [{ at: new Date().toISOString(), state: 'SEARCHING', note: 'Looking for a nearby Boda' }],
      createdAt: new Date().toISOString(),
    };
    this.rides.set(ride.id, ride);
    this.persistence.persist('booking_ride', ride.id, ride);
    this.analytics.record(riderId, 'ride_requested', { rideId: ride.id, fare: ride.fare, paymentMethod: ride.paymentMethod });
    return ride;
  }

  /** Rides waiting for a driver — source of real driver offers. */
  pendingRides(): Ride[] {
    const now = Date.now();
    return [...this.rides.values()]
      .filter((r) => r.state === 'SEARCHING' && now - new Date(r.createdAt).getTime() < PENDING_WINDOW_MS)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }

  findRide(rideId: string): Ride {
    const ride = this.rides.get(rideId);
    if (!ride) throw new NotFoundException({ code: 'RIDE_NOT_FOUND' });
    return ride;
  }

  /** Called by DriverService when a driver accepts the rider's offer. */
  assignDriver(
    rideId: string,
    driver: AssignedDriver,
    driverTripId: string,
    pickupCode: string,
  ): Ride {
    const ride = this.findRide(rideId);
    if (ride.state !== 'SEARCHING') throw new BadRequestException({ code: 'RIDE_NOT_ASSIGNABLE' });
    ride.state = 'ASSIGNED';
    ride.driver = driver;
    ride.driverTripId = driverTripId;
    ride.pickupCode = pickupCode;
    ride.events.push({ at: new Date().toISOString(), state: 'ASSIGNED', note: 'Driver assigned' });
    this.persistence.persist('booking_ride', ride.id, ride);
    this.analytics.record(ride.riderId, 'ride_assigned', { rideId: ride.id, driverId: driver.driverId });
    void this.notifications.send(ride.riderId, 'Boda on the way', `${driver.name ?? 'Your driver'} accepted your ride. Pickup code ${pickupCode}.`, { rideId: ride.id, type: 'RIDE_ASSIGNED' });
    return ride;
  }

  /** Called by DriverService as the driver moves through the trip. */
  updateRideForDriver(rideId: string, driverState: 'ARRIVED' | 'IN_PROGRESS' | 'COMPLETED' | 'CANCELLED'): Ride {
    const ride = this.findRide(rideId);
    const map: Record<string, RideState> = {
      ARRIVED: 'ARRIVED',
      IN_PROGRESS: 'IN_PROGRESS',
      COMPLETED: 'COMPLETED',
      CANCELLED: 'CANCELLED',
    };
    ride.state = map[driverState];
    ride.events.push({ at: new Date().toISOString(), state: ride.state });
    this.persistence.persist('booking_ride', ride.id, ride);
    const copy: Record<string, { title: string; body: string }> = {
      ARRIVED: { title: 'Your Boda has arrived', body: 'Meet your driver at the pickup point.' },
      IN_PROGRESS: { title: 'Trip started', body: 'Enjoy the ride — share the trip with someone you trust.' },
      COMPLETED: { title: 'Trip complete', body: `Fare KES ${ride.fare}. Thanks for riding with Uko?.` },
      CANCELLED: { title: 'Ride cancelled', body: 'Your ride was cancelled.' },
    };
    if (ride.state === 'COMPLETED') this.analytics.record(ride.riderId, 'trip_completed', { rideId: ride.id, fare: ride.fare });
    const message = copy[ride.state];
    if (message) void this.notifications.send(ride.riderId, message.title, message.body, { rideId: ride.id, type: ride.state });
    return ride;
  }

  getRide(riderId: string, rideId: string): Ride {
    const ride = this.findRide(rideId);
    if (ride.riderId !== riderId) throw new NotFoundException({ code: 'RIDE_NOT_FOUND' });
    return ride;
  }

  allRides(): Ride[] {
    return [...this.rides.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  cancelRideByOps(rideId: string, reason?: string, note?: string): Ride {
    const ride = this.findRide(rideId);
    if (['COMPLETED', 'CANCELLED'].includes(ride.state)) {
      throw new BadRequestException({ code: 'RIDE_NOT_CANCELLABLE' });
    }
    const label = reason?.trim() || 'Cancelled by dispatch';
    ride.state = 'CANCELLED';
    ride.cancellation = {
      code: 'DISPATCH_CANCELLED',
      label,
      ...(note ? { note } : {}),
      by: 'dispatch',
      at: new Date().toISOString(),
    };
    ride.events.push({ at: new Date().toISOString(), state: 'CANCELLED', note: `Cancelled by dispatch: ${label}` });
    this.persistence.persist('booking_ride', ride.id, ride);
    if (ride.driver?.driverId) {
      void this.notifications.send(ride.driver.driverId, 'Ride cancelled by dispatch', `${label}.`, { rideId: ride.id, type: 'RIDE_CANCELLED' });
    }
    void this.notifications.send(ride.riderId, 'Ride cancelled by dispatch', `${label}.`, { rideId: ride.id, type: 'RIDE_CANCELLED' });
    return ride;
  }

  listRides(riderId: string): Ride[] {
    return [...this.rides.values()]
      .filter((r) => r.riderId === riderId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  cancelRide(riderId: string, rideId: string, reason?: string, note?: string): Ride {
    const ride = this.getRide(riderId, rideId);
    if (ride.state === 'ARRIVED' || ride.state === 'IN_PROGRESS') {
      throw new BadRequestException({
        code: 'RIDE_ARRIVED_DISPATCH_ONLY',
        message: 'Your driver has already arrived. Please contact dispatch to cancel this ride.',
      });
    }
    if (!['SEARCHING', 'ASSIGNED', 'ARRIVING'].includes(ride.state)) {
      throw new BadRequestException({ code: 'RIDE_NOT_CANCELLABLE' });
    }
    const label = reason?.trim() || 'Cancelled by rider';
    ride.state = 'CANCELLED';
    ride.cancellation = {
      code: 'RIDER_CANCELLED',
      label,
      ...(note ? { note } : {}),
      by: 'rider',
      at: new Date().toISOString(),
    };
    ride.events.push({ at: new Date().toISOString(), state: 'CANCELLED', note: `Cancelled by rider: ${label}` });
    this.persistence.persist('booking_ride', ride.id, ride);
    if (ride.driver?.driverId) {
      void this.notifications.send(ride.driver.driverId, 'Rider cancelled the ride', `Reason: ${label}.`, { rideId: ride.id, type: 'RIDE_CANCELLED' });
    }
    return ride;
  }

  cancelRideByDriver(rideId: string, reason?: string): Ride {
    const ride = this.findRideById(rideId);
    if (!ride) throw new BadRequestException({ code: 'RIDE_NOT_FOUND' });
    if (['COMPLETED', 'CANCELLED'].includes(ride.state)) {
      throw new BadRequestException({ code: 'RIDE_NOT_CANCELLABLE' });
    }
    const label = reason?.trim() || 'Cancelled by driver';
    ride.state = 'CANCELLED';
    ride.cancellation = {
      code: 'DRIVER_CANCELLED',
      label,
      by: 'driver',
      at: new Date().toISOString(),
    };
    ride.events.push({ at: new Date().toISOString(), state: 'CANCELLED', note: `Cancelled by driver: ${label}` });
    this.persistence.persist('booking_ride', ride.id, ride);
    void this.notifications.send(ride.riderId, 'Driver cancelled the ride', `${label}. Please request another Boda.`, { rideId: ride.id, type: 'RIDE_CANCELLED' });
    return ride;
  }

  /** Internal lookup used by driver/status syncing. */
  findRideById(rideId: string): Ride | undefined {
    return this.rides.get(rideId);
  }
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
