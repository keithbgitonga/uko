import { Injectable, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, randomInt, randomUUID } from 'node:crypto';
import * as jwt from 'jsonwebtoken';
import { DatabaseService } from '../database/database.service';
import { SmsService } from './sms.service';
import { TEST_ACCOUNTS, TEST_OPS_ROLES, TestAccount, TestRole } from './test-accounts';

export interface DevUser {
  id: string;
  phone: string;
  name: string | null;
  createdAt: string;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: number;
}

interface OtpRecord {
  code: string;
  expiresAt: number;
  attempts: number;
}

/**
 * Auth with two stores:
 * - AUTH_STORE=postgres (or DATABASE_URL present): users and refresh tokens in Postgres.
 * - AUTH_STORE=memory: in-memory walking skeleton (tablet bench without a database).
 * OTP delivery remains a dev stub until the SMS provider adapter lands.
 */
@Injectable()
export class AuthService {
  private readonly otps = new Map<string, OtpRecord>();
  private readonly memoryUsersByPhone = new Map<string, DevUser>();
  private readonly memoryRefreshTokens = new Map<string, { userId: string; expiresAt: number }>();

  constructor(
    private readonly config: ConfigService,
    private readonly db: DatabaseService,
    private readonly sms: SmsService,
  ) {}

  private get usePostgres(): boolean {
    return this.config.get<string>('authStore') === 'postgres';
  }

  testAccounts(): TestAccount[] {
    if (!this.config.get<boolean>('allowTestLogins')) {
      throw new NotFoundException({ code: 'TEST_LOGINS_DISABLED' });
    }
    return TEST_ACCOUNTS;
  }

  isTestOpsPhone(phone: string): boolean {
    return (
      this.config.get<boolean>('allowTestLogins') === true &&
      TEST_ACCOUNTS.some((a) => TEST_OPS_ROLES.includes(a.role) && a.phone === phone)
    );
  }

  async testLogin(role: TestRole): Promise<{ user: DevUser; tokens: TokenPair; role: TestRole; account: TestAccount }> {
    if (!this.config.get<boolean>('allowTestLogins')) {
      throw new NotFoundException({ code: 'TEST_LOGINS_DISABLED' });
    }
    const account = TEST_ACCOUNTS.find((a) => a.role === role);
    if (!account) throw new NotFoundException({ code: 'TEST_ROLE_UNKNOWN' });
    const user = this.usePostgres
      ? await this.upsertUser(account.phone, account.name)
      : this.memoryUser(account.phone, account.name);
    const tokens = await this.issueTokens(user.id);
    return { user, tokens, role, account };
  }

  async requestOtp(phone: string) {
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const ttl = this.config.get<number>('otp.ttlSeconds') ?? 300;
    this.otps.set(phone, { code, expiresAt: Date.now() + ttl * 1000, attempts: 0 });

    const delivery = await this.sms.sendOtp(phone, code);
    const expose = this.config.get<boolean>('otp.exposeDevOtp');
    const isDev = (this.config.get<string>('env') ?? 'development') !== 'production';
    return {
      sent: true,
      channel: delivery.channel,
      expiresInSeconds: ttl,
      ...(expose && isDev && delivery.channel === 'dev' ? { dev_code: code } : {}),
    };
  }

  async verifyOtp(phone: string, code: string): Promise<{ user: DevUser; tokens: TokenPair }> {
    this.assertOtp(phone, code);
    this.otps.delete(phone);

    const user = this.usePostgres ? await this.upsertUser(phone) : this.memoryUser(phone);
    const tokens = await this.issueTokens(user.id);
    return { user, tokens };
  }

  async refresh(token: string): Promise<TokenPair> {
    const payload = this.verifyJwt(token, 'refresh');
    if (this.usePostgres) {
      const result = await this.db.pool.query(
        `SELECT user_id FROM refresh_tokens
         WHERE token_hash = $1 AND revoked_at IS NULL AND rotated_at IS NULL AND expires_at > now()`,
        [hashToken(token)],
      );
      if (result.rowCount === 0) throw new UnauthorizedException({ code: 'REFRESH_EXPIRED_OR_ROTATED' });
      await this.db.pool.query('UPDATE refresh_tokens SET rotated_at = now() WHERE token_hash = $1', [hashToken(token)]);
      return this.issueTokens(payload.sub);
    }

    const stored = this.memoryRefreshTokens.get(token);
    if (!stored || stored.expiresAt < Date.now()) {
      throw new UnauthorizedException({ code: 'REFRESH_EXPIRED_OR_ROTATED' });
    }
    // Rotate: old refresh token can never be reused.
    this.memoryRefreshTokens.delete(token);
    return this.issueTokens(payload.sub);
  }

  async logout(token: string): Promise<{ loggedOut: boolean; userId: string }> {
    const payload = this.verifyJwt(token, 'refresh');
    if (this.usePostgres) {
      await this.db.pool.query(
        'UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL',
        [hashToken(token)],
      );
    } else {
      this.memoryRefreshTokens.delete(token);
    }
    return { loggedOut: true, userId: payload.sub };
  }

  async verifyAccess(token: string): Promise<DevUser> {
    const payload = this.verifyJwt(token, 'access');
    if (this.usePostgres) {
      const result = await this.db.pool.query(
        'SELECT id, phone, name, created_at FROM users WHERE id = $1 AND status = $2',
        [payload.sub, 'active'],
      );
      if (result.rowCount === 0) throw new UnauthorizedException({ code: 'ACCESS_INVALID' });
      const row = result.rows[0];
      return { id: row.id, phone: row.phone, name: row.name, createdAt: row.created_at.toISOString() };
    }
    const user = [...this.memoryUsersByPhone.values()].find((u) => u.id === payload.sub);
    if (!user) throw new UnauthorizedException({ code: 'ACCESS_INVALID' });
    return user;
  }

  private assertOtp(phone: string, code: string): void {
    const record = this.otps.get(phone);
    if (!record) throw new UnauthorizedException({ code: 'OTP_NOT_REQUESTED' });
    if (Date.now() > record.expiresAt) {
      this.otps.delete(phone);
      throw new UnauthorizedException({ code: 'OTP_EXPIRED' });
    }
    const maxAttempts = this.config.get<number>('otp.maxAttempts') ?? 5;
    if (record.attempts >= maxAttempts) {
      this.otps.delete(phone);
      throw new UnauthorizedException({ code: 'OTP_TOO_MANY_ATTEMPTS' });
    }
    if (record.code !== code) {
      record.attempts += 1;
      throw new UnauthorizedException({ code: 'OTP_INVALID' });
    }
  }

  private memoryUser(phone: string, name: string | null = null): DevUser {
    let user = this.memoryUsersByPhone.get(phone);
    if (!user) {
      user = {
        id: `dev_${randomInt(100000, 999999)}`,
        phone,
        name,
        createdAt: new Date().toISOString(),
      };
      this.memoryUsersByPhone.set(phone, user);
    }
    return user;
  }

  private async upsertUser(phone: string, name: string | null = null): Promise<DevUser> {
    const result = await this.db.pool.query(
      `INSERT INTO users (phone, name) VALUES ($1, $2)
       ON CONFLICT (phone) DO UPDATE SET name = COALESCE(users.name, EXCLUDED.name), updated_at = now()
       RETURNING id, phone, name, created_at`,
      [phone, name],
    );
    const row = result.rows[0];
    return { id: row.id, phone: row.phone, name: row.name, createdAt: row.created_at.toISOString() };
  }

  private verifyJwt(token: string, expectedTyp: 'access' | 'refresh'): { sub: string; typ: string } {
    const secret = this.config.get<string>(
      expectedTyp === 'access' ? 'jwt.accessSecret' : 'jwt.refreshSecret',
    );
    let payload: { sub?: string; typ?: string };
    try {
      payload = jwt.verify(token, secret) as { sub?: string; typ?: string };
    } catch {
      throw new UnauthorizedException({
        code: expectedTyp === 'access' ? 'ACCESS_INVALID' : 'REFRESH_INVALID',
      });
    }
    if (!payload.sub || payload.typ !== expectedTyp) {
      throw new UnauthorizedException({
        code: expectedTyp === 'access' ? 'ACCESS_INVALID' : 'REFRESH_INVALID',
      });
    }
    return { sub: payload.sub, typ: payload.typ };
  }

  private async issueTokens(userId: string): Promise<TokenPair> {
    const accessTtl = this.config.get<number>('jwt.accessTtl') ?? 900;
    const refreshTtl = this.config.get<number>('jwt.refreshTtl') ?? 2592000;
    const accessToken = jwt.sign(
      { sub: userId, typ: 'access', jti: randomUUID() },
      this.config.get<string>('jwt.accessSecret'),
      { expiresIn: accessTtl },
    );
    const refreshToken = jwt.sign(
      { sub: userId, typ: 'refresh', jti: randomUUID() },
      this.config.get<string>('jwt.refreshSecret'),
      { expiresIn: refreshTtl },
    );

    if (this.usePostgres) {
      await this.db.pool.query(
        `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, now() + ($3 || ' seconds')::interval)`,
        [userId, hashToken(refreshToken), String(refreshTtl)],
      );
    } else {
      this.memoryRefreshTokens.set(refreshToken, {
        userId,
        expiresAt: Date.now() + refreshTtl * 1000,
      });
    }

    return {
      accessToken,
      refreshToken,
      tokenType: 'Bearer',
      expiresIn: accessTtl,
    };
  }
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
