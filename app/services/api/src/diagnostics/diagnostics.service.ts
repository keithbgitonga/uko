import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class DiagnosticsService {
  constructor(private readonly db: DatabaseService) {}

  async record(input: {
    userId?: string;
    app: string;
    version?: string;
    platform?: string;
    message: string;
    stack?: string;
  }) {
    const id = `err_${randomUUID()}`;
    await this.db.pool.query(
      `INSERT INTO client_errors (id, user_id, app, version, platform, message, stack)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [id, input.userId ?? null, input.app, input.version ?? null, input.platform ?? null, input.message.slice(0, 4000), (input.stack ?? '').slice(0, 16000)],
    );
    return { id };
  }

  async count24h(): Promise<number> {
    const result = await this.db.pool.query(
      "SELECT count(*)::int AS n FROM client_errors WHERE created_at > now() - interval '24 hours'",
    );
    return result.rows[0].n;
  }

  async recent(limit = 50) {
    const result = await this.db.pool.query('SELECT * FROM client_errors ORDER BY created_at DESC LIMIT $1', [limit]);
    return result.rows.map((r) => ({
      id: r.id,
      app: r.app,
      version: r.version,
      platform: r.platform,
      message: r.message,
      stack: r.stack,
      createdAt: new Date(r.created_at).toISOString(),
    }));
  }
}
