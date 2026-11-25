import { HttpException, HttpStatus, Injectable, NestMiddleware } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NextFunction, Request, Response } from 'express';

/** Simple in-memory rate limiter for OTP endpoints (single-instance pilot). */
@Injectable()
export class OtpRateLimitMiddleware implements NestMiddleware {
  private readonly hits = new Map<string, number[]>();

  constructor(private readonly config: ConfigService) {}

  use(req: Request, res: Response, next: NextFunction): void {
    const path = req.path;
    const phone = typeof req.body?.phone === 'string' ? req.body.phone : '';
    const ip = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const now = Date.now();

    if (path.endsWith('/auth/otp/request')) {
      const perPhone = this.config.get<number>('rateLimit.otpPerPhoneHour') ?? 3;
      const perIp = this.config.get<number>('rateLimit.otpPerIpHour') ?? 10;
      if (!this.allow(`req:phone:${phone}`, now, 3600_000, perPhone) ||
          !this.allow(`req:ip:${ip}`, now, 3600_000, perIp)) {
        throw new HttpException(
          { code: 'RATE_LIMITED', message: 'Too many OTP requests. Try again later.' },
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    } else if (path.endsWith('/auth/otp/verify')) {
      const perPhone = this.config.get<number>('rateLimit.verifyPerPhone10Min') ?? 10;
      if (!this.allow(`verify:phone:${phone}`, now, 600_000, perPhone)) {
        throw new HttpException(
          { code: 'RATE_LIMITED', message: 'Too many verification attempts. Try again later.' },
          HttpStatus.TOO_MANY_REQUESTS,
        );
      }
    }
    next();
  }

  private allow(key: string, now: number, windowMs: number, limit: number): boolean {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (recent.length >= limit) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(key, recent);
    return true;
  }
}
