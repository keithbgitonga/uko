import { Injectable } from '@nestjs/common';
import { createSign } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';

export interface DeviceToken {
  id: string;
  userId: string;
  token: string;
  platform: string;
}

/**
 * Push notifications with an outbox. `PUSH_PROVIDER=dev` logs deliveries;
 * `fcm` posts to the FCM HTTP legacy endpoint (or a fake gateway in tests).
 */
@Injectable()
export class NotificationsService {
  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
  ) {}

  async registerDevice(userId: string, token: string, platform = 'android'): Promise<DeviceToken> {
    const id = `dt_${randomUUID()}`;
    const result = await this.db.pool.query(
      `INSERT INTO device_tokens (id, user_id, token, platform, updated_at)
       VALUES ($1,$2,$3,$4,now())
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = now()
       RETURNING id, user_id, token, platform`,
      [id, userId, token, platform],
    );
    return rowToDevice(result.rows[0]);
  }

  async devices(userId: string): Promise<DeviceToken[]> {
    const result = await this.db.pool.query('SELECT * FROM device_tokens WHERE user_id = $1 ORDER BY updated_at DESC', [userId]);
    return result.rows.map(rowToDevice);
  }

  async list(userId: string, limit = 50) {
    const result = await this.db.pool.query(
      'SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
      [userId, limit],
    );
    return result.rows.map(rowToNotification);
  }

  /** Queues and attempts a push; never throws to the caller. */
  async send(userId: string, title: string, body: string, data: Record<string, unknown> = {}): Promise<void> {
    const id = `nt_${randomUUID()}`;
    const provider = this.config.get<string>('push.provider') ?? 'dev';
    const hasKey = !!this.config.get<string>('push.serverKey');
    const serviceAccount = !!this.config.get<string>('push.projectId') &&
      !!this.config.get<string>('push.clientEmail') &&
      !!this.config.get<string>('push.privateKey');
    let status = 'SENT';
    let providerId: string | null = null;
    let error: string | null = null;
    try {
      if (provider === 'fcm' && serviceAccount) {
        // Firebase Cloud Messaging HTTP v1 (service-account OAuth2).
        const devices = await this.devices(userId);
        if (devices.length === 0) {
          status = 'FAILED';
          error = 'no_device_tokens';
        } else {
          const accessToken = await this.fcmAccessToken();
          const base = (this.config.get<string>('push.baseUrl') ?? '').replace(/\/$/, '');
          const projectId = this.config.get<string>('push.projectId');
          const stringData = Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)]));
          let successes = 0;
          const failures: string[] = [];
          for (const device of devices) {
            const response = await fetch(`${base}/v1/projects/${projectId}/messages:send`, {
              method: 'POST',
              headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
              body: JSON.stringify({
                message: { token: device.token, notification: { title, body }, data: stringData },
              }),
            });
            const result: any = await response.json().catch(() => ({}));
            if (response.ok) {
              successes += 1;
              providerId = result.name ?? providerId;
            } else {
              failures.push(result?.error?.message ? `${result.error.status ?? response.status}: ${String(result.error.message).slice(0, 180)}` : `http_${response.status}`);
            }
          }
          if (successes === 0) {
            status = 'FAILED';
            error = failures.join(',') || 'fcm_v1_failed';
          }
        }
      } else if (provider === 'fcm' && hasKey) {
        // Legacy FCM endpoint (kept for projects that still issue server keys).
        const devices = await this.devices(userId);
        if (devices.length === 0) {
          status = 'FAILED';
          error = 'no_device_tokens';
        } else {
          const base = (this.config.get<string>('push.baseUrl') ?? '').replace(/\/$/, '');
          const payload =
            devices.length === 1
              ? { to: devices[0].token, notification: { title, body }, data }
              : { registration_ids: devices.map((d) => d.token), notification: { title, body }, data };
          const response = await fetch(`${base}/fcm/send`, {
            method: 'POST',
            headers: {
              authorization: `key=${this.config.get<string>('push.serverKey')}`,
              'content-type': 'application/json',
            },
            body: JSON.stringify(payload),
          });
          const result: any = await response.json().catch(() => ({}));
          if (!response.ok) {
            status = 'FAILED';
            error = `fcm_http_${response.status}`;
          } else {
            providerId = result.results?.[0]?.message_id ?? null;
          }
        }
      } else {
        console.log(`[dev-push] ${maskUser(userId)} · ${title} — ${body}`);
      }
    } catch (err) {
      status = 'FAILED';
      error = err instanceof Error ? err.message : 'push_failed';
    }
    await this.db.pool
      .query(
        `INSERT INTO notifications (id, user_id, title, body, data, channel, status, provider_id, error, sent_at)
         VALUES ($1,$2,$3,$4,$5,'push',$6,$7,$8,$9)`,
        [id, userId, title, body, JSON.stringify(data), status, providerId, error, status === 'SENT' ? new Date() : null],
      )
      .catch((err) => console.error(`notification write failed: ${err.message}`));
  }

  private fcmToken?: { value: string; expiresAt: number };

  private async fcmAccessToken(): Promise<string> {
    if (this.fcmToken && this.fcmToken.expiresAt > Date.now() + 60_000) return this.fcmToken.value;
    const clientEmail = this.config.get<string>('push.clientEmail')!;
    const privateKey = this.config.get<string>('push.privateKey')!;
    const oauthUrl = this.config.get<string>('push.oauthUrl')!;
    const now = Math.floor(Date.now() / 1000);
    const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = base64url(JSON.stringify({
      iss: clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: oauthUrl,
      iat: now,
      exp: now + 3600,
    }));
    const signer = createSign('RSA-SHA256');
    signer.update(`${header}.${claims}`);
    const signature = signer.sign(privateKey).toString('base64url');
    const response = await fetch(oauthUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: `${header}.${claims}.${signature}`,
      }),
    });
    const body: any = await response.json().catch(() => ({}));
    if (!response.ok || !body.access_token) throw new Error(`FCM OAuth failed: HTTP ${response.status}`);
    this.fcmToken = { value: body.access_token, expiresAt: Date.now() + (Number(body.expires_in) || 3600) * 1000 };
    return this.fcmToken.value;
  }
}

function rowToDevice(row: any): DeviceToken {
  return { id: row.id, userId: row.user_id, token: row.token, platform: row.platform };
}

function rowToNotification(row: any) {
  return {
    id: row.id,
    title: row.title,
    body: row.body,
    data: row.data,
    channel: row.channel,
    status: row.status,
    error: row.error,
    createdAt: new Date(row.created_at).toISOString(),
    sentAt: row.sent_at ? new Date(row.sent_at).toISOString() : null,
  };
}

function maskUser(userId: string): string {
  return userId ? `${userId.slice(0, 8)}…` : 'unknown';
}

function base64url(value: string): string {
  return Buffer.from(value).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
}
