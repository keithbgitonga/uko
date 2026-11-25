import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class AnalyticsService {
  constructor(private readonly db: DatabaseService) {}

  /** Fire-and-forget product event; never blocks the caller. */
  record(userId: string | null, event: string, props: Record<string, unknown> = {}): void {
    const id = `ev_${randomUUID()}`;
    void this.db.pool
      .query('INSERT INTO analytics_events (id, user_id, event, props) VALUES ($1,$2,$3,$4)', [id, userId, event, JSON.stringify(props)])
      .catch((err) => console.error(`analytics write failed: ${err.message}`));
  }

  async recent(limit = 100) {
    const result = await this.db.pool.query(
      'SELECT event, count(*)::int AS count FROM analytics_events WHERE created_at > now() - interval \'24 hours\' GROUP BY event ORDER BY count DESC LIMIT $1',
      [limit],
    );
    return result.rows;
  }
}
