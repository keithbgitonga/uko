import { Body, Controller, Get, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { IsObject, IsOptional, IsString } from 'class-validator';
import { DatabaseService } from '../database/database.service';
import { AuthService, DevUser } from '../identity/auth.service';
import { AlertsService } from './alerts.service';
import { AnalyticsService } from './analytics.service';
import { MetricsService } from './metrics.service';

export class AnalyticsEventDto {
  @IsString()
  event!: string;

  @IsOptional()
  @IsObject()
  props?: Record<string, unknown>;
}

@Controller()
export class ObservabilityController {
  constructor(
    private readonly metrics: MetricsService,
    private readonly analytics: AnalyticsService,
    private readonly db: DatabaseService,
    private readonly auth: AuthService,
    private readonly alertsService: AlertsService,
  ) {}

  @Get('health/ready')
  async ready() {
    const started = Date.now();
    try {
      await this.db.pool.query('SELECT 1');
      const counts = await this.db.pool.query(
        `SELECT (SELECT count(*)::int FROM rides) AS rides,
                (SELECT count(*)::int FROM users) AS users,
                (SELECT count(*)::int FROM notifications) AS notifications`,
      );
      return {
        status: 'ok',
        checks: { database: { ok: true, latencyMs: Date.now() - started } },
        counts: counts.rows[0],
      };
    } catch (err) {
      return {
        status: 'degraded',
        checks: { database: { ok: false, error: err instanceof Error ? err.message : 'db error' } },
      };
    }
  }

  @Get('health/alerts')
  async alerts() {
    return this.alertsService.evaluate();
  }

  @Get('metrics')
  async summary() {
    const counts = await this.db.pool.query(
      `SELECT (SELECT count(*)::int FROM rides) AS rides,
              (SELECT count(*)::int FROM payments) AS payments,
              (SELECT count(*)::int FROM safety_incidents) AS incidents,
              (SELECT count(*)::int FROM notifications) AS notifications,
              (SELECT count(*)::int FROM analytics_events) AS events,
              (SELECT count(*)::int FROM client_errors) AS client_errors`,
    );
    return {
      ...this.metrics.snapshot(),
      database: { ok: true, counts: counts.rows[0] },
      events24h: await this.analytics.recent(20),
    };
  }

  @Post('analytics/events')
  async ingest(@Headers('authorization') authHeader: string | undefined, @Body() dto: AnalyticsEventDto) {
    const user = await this.requireUser(authHeader);
    this.analytics.record(user.id, dto.event, dto.props ?? {});
    return { accepted: true };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
