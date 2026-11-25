import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { BookingService } from '../booking/booking.service';
import { DatabaseService } from '../database/database.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AnalyticsService } from '../observability/analytics.service';

export interface RideRating {
  id: string;
  rideId: string;
  riderId: string;
  driverId?: string;
  rating: number;
  comment?: string;
  createdAt: string;
}

@Injectable()
export class RatingsService {
  constructor(
    private readonly booking: BookingService,
    private readonly db: DatabaseService,
    private readonly notifications: NotificationsService,
    private readonly analytics: AnalyticsService,
  ) {}

  async rate(riderId: string, rideId: string, rating: number, comment?: string): Promise<RideRating> {
    const ride = this.booking.getRide(riderId, rideId);
    if (ride.state !== 'COMPLETED') {
      throw new BadRequestException({ code: 'RIDE_NOT_COMPLETED', message: 'You can rate a ride after it completes' });
    }
    const driverId = ride.driver?.driverId ?? null;
    const id = `rt_${randomUUID()}`;
    const result = await this.db.pool.query(
      `INSERT INTO ride_ratings (id, ride_id, rider_id, driver_id, rating, comment)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (ride_id) DO UPDATE SET rating = EXCLUDED.rating, comment = EXCLUDED.comment
       RETURNING *`,
      [id, rideId, riderId, driverId, rating, comment ?? null],
    );
    const saved = toRating(result.rows[0]);
    this.analytics.record(riderId, 'rating_submitted', { rideId, rating, hasComment: !!comment });
    if (driverId) {
      const stars = '★'.repeat(rating);
      void this.notifications.send(driverId, 'New rating', `You received ${rating}/5 ${stars} for a recent trip.`, { rideId, rating, type: 'RATING' });
    }
    return saved;
  }

  async forRide(riderId: string, rideId: string): Promise<RideRating | null> {
    const result = await this.db.pool.query('SELECT * FROM ride_ratings WHERE ride_id = $1 AND rider_id = $2', [rideId, riderId]);
    if (result.rowCount === 0) throw new NotFoundException({ code: 'RATING_NOT_FOUND' });
    return toRating(result.rows[0]);
  }

  async driverSummary(driverId: string) {
    const result = await this.db.pool.query(
      `SELECT count(*)::int AS count, COALESCE(avg(rating), 0)::numeric(3,2) AS average FROM ride_ratings WHERE driver_id = $1`,
      [driverId],
    );
    return { count: result.rows[0].count, average: Number(result.rows[0].average) };
  }
}

function toRating(row: any): RideRating {
  return {
    id: row.id,
    rideId: row.ride_id,
    riderId: row.rider_id,
    ...(row.driver_id ? { driverId: row.driver_id } : {}),
    rating: row.rating,
    ...(row.comment ? { comment: row.comment } : {}),
    createdAt: new Date(row.created_at).toISOString(),
  };
}
