import { Global, Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { DiagnosticsModule } from '../diagnostics/diagnostics.module';
import { AuthModule } from '../identity/auth.module';
import { AlertsService } from './alerts.service';
import { AnalyticsService } from './analytics.service';
import { MetricsInterceptor } from './metrics.interceptor';
import { MetricsService } from './metrics.service';
import { ObservabilityController } from './observability.controller';

@Global()
@Module({
  imports: [AuthModule, DiagnosticsModule],
  controllers: [ObservabilityController],
  providers: [MetricsService, AnalyticsService, AlertsService, { provide: APP_INTERCEPTOR, useClass: MetricsInterceptor }],
  exports: [MetricsService, AnalyticsService],
})
export class ObservabilityModule {}
