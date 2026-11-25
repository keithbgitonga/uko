import { Injectable } from '@nestjs/common';

/** Process-local HTTP counters for the pilot dashboard (single instance). */
@Injectable()
export class MetricsService {
  private readonly startedAt = Date.now();
  private requests = 0;
  private failures = 0;
  private readonly byStatus = new Map<number, number>();
  private totalDurationMs = 0;

  record(status: number, durationMs: number): void {
    this.requests += 1;
    this.totalDurationMs += durationMs;
    this.byStatus.set(status, (this.byStatus.get(status) ?? 0) + 1);
    if (status >= 500) this.failures += 1;
  }

  snapshot() {
    const statuses: Record<string, number> = {};
    for (const [status, count] of [...this.byStatus.entries()].sort((a, b) => a[0] - b[0])) statuses[String(status)] = count;
    return {
      uptimeSeconds: Math.round((Date.now() - this.startedAt) / 1000),
      requests: {
        total: this.requests,
        failures: this.failures,
        byStatus: statuses,
        averageMs: this.requests === 0 ? 0 : Math.round(this.totalDurationMs / this.requests),
      },
    };
  }
}
