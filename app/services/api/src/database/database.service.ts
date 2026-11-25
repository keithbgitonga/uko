import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';

/**
 * Thin Postgres/PostGIS pool. Repositories land in Sprint 1 tasks FND-2/FND-5.
 * The walking skeleton does not require a live database to boot.
 */
@Injectable()
export class DatabaseService implements OnModuleDestroy {
  readonly pool: Pool;

  constructor(config: ConfigService) {
    const ssl = config.get<boolean>('databaseSsl') ? { rejectUnauthorized: false } : undefined;
    this.pool = new Pool({
      connectionString: config.get<string>('databaseUrl'),
      ssl,
      max: 10,
      idleTimeoutMillis: 30_000,
    });
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }

  async ping(): Promise<boolean> {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }
}
