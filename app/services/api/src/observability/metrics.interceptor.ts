import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { MetricsService } from './metrics.service';

@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  constructor(private readonly metrics: MetricsService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const started = Date.now();
    const response = context.switchToHttp().getResponse();
    return next.handle().pipe(
      tap({
        next: () => this.metrics.record(response.statusCode ?? 200, Date.now() - started),
        error: (err) => this.metrics.record(err?.status ?? 500, Date.now() - started),
      }),
    );
  }
}
