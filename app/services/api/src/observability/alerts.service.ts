import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../database/database.service';
import { DiagnosticsService } from '../diagnostics/diagnostics.service';
import { MetricsService } from './metrics.service';

export interface Alert {
  level: 'info' | 'warning' | 'critical';
  code: string;
  message: string;
}

/**
 * Evaluates operational alerts and forwards them to an optional webhook
 * (Slack-compatible payload) when the alert set changes.
 */
@Injectable()
export class AlertsService {
  private lastSignature = '';

  constructor(
    private readonly db: DatabaseService,
    private readonly diagnostics: DiagnosticsService,
    private readonly metrics: MetricsService,
    private readonly config: ConfigService,
  ) {}

  async evaluate(): Promise<{ status: string; alerts: Alert[]; checkedAt: string }> {
    const alerts: Alert[] = [];
    try {
      await this.db.pool.query('SELECT 1');
    } catch {
      alerts.push({ level: 'critical', code: 'DB_DOWN', message: 'Database is unreachable' });
    }
    try {
      const staleSos = await this.db.pool.query(
        `SELECT count(*)::int AS n FROM safety_incidents
         WHERE state IN ('OPEN','ACKED') AND created_at::timestamptz < now() - interval '15 minutes'`,
      );
      if (staleSos.rows[0].n > 0) {
        alerts.push({ level: 'critical', code: 'SOS_UNATTENDED', message: `${staleSos.rows[0].n} SOS incident(s) open for more than 15 minutes` });
      }
      const failedNotifications = await this.db.pool.query(
        `SELECT count(*)::int AS n FROM notifications WHERE status='FAILED' AND created_at > now() - interval '24 hours'`,
      );
      if (failedNotifications.rows[0].n > 0) {
        alerts.push({ level: 'warning', code: 'PUSH_FAILURES', message: `${failedNotifications.rows[0].n} notification(s) failed in the last 24h` });
      }
      const pendingDocs = await this.db.pool.query(
        `SELECT count(*)::int AS n FROM driver_documents WHERE status='PENDING' AND created_at < now() - interval '24 hours'`,
      );
      if (pendingDocs.rows[0].n > 0) {
        alerts.push({ level: 'warning', code: 'DOCS_PENDING', message: `${pendingDocs.rows[0].n} driver document(s) pending for more than 24h` });
      }
      const expiringDocs = await this.db.pool.query(
        `SELECT count(*)::int AS n FROM driver_documents
         WHERE status='APPROVED' AND expires_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
           AND expires_at::date <= current_date + 14`,
      );
      if (expiringDocs.rows[0].n > 0) {
        alerts.push({ level: 'warning', code: 'DOCS_EXPIRING', message: `${expiringDocs.rows[0].n} approved document(s) expire within 14 days` });
      }
      const errors = await this.diagnostics.count24h();
      if (errors > 0) {
        alerts.push({ level: 'warning', code: 'CLIENT_ERRORS', message: `${errors} client error report(s) in the last 24h` });
      }
      const http = this.metrics.snapshot().requests;
      if (http.total > 20 && http.failures / http.total > 0.05) {
        alerts.push({ level: 'warning', code: 'HTTP_FAILURES', message: `HTTP failure rate ${Math.round((http.failures / http.total) * 100)}%` });
      }
    } catch (err) {
      console.error(`alerts evaluation failed: ${err instanceof Error ? err.message : err}`);
    }
    const status = alerts.some((a) => a.level === 'critical') ? 'critical' : alerts.length > 0 ? 'warning' : 'ok';
    const result = { status, alerts, checkedAt: new Date().toISOString() };
    await this.notify(result);
    return result;
  }

  private async notify(result: { status: string; alerts: Alert[]; checkedAt: string }): Promise<void> {
    const webhookUrl = this.config.get<string>('alerts.webhookUrl');
    if (!webhookUrl || result.alerts.length === 0) return;
    const signature = JSON.stringify(result.alerts.map((a) => `${a.level}:${a.code}:${a.message}`));
    if (signature === this.lastSignature) return;
    this.lastSignature = signature;
    const text = `Uko? ${result.status.toUpperCase()} alert\n` +
      result.alerts.map((a) => `• [${a.level}] ${a.code}: ${a.message}`).join('\n');
    try {
      const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ text }),
      });
      if (!response.ok) console.error(`alert webhook returned ${response.status}`);
    } catch (err) {
      console.error(`alert webhook failed: ${err instanceof Error ? err.message : err}`);
    }
  }
}
