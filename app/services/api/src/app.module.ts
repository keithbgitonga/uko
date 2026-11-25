import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import configuration from './config/configuration';
import { DatabaseModule } from './database/database.module';
import { PersistenceModule } from './persistence/persistence.module';
import { HealthModule } from './health/health.module';
import { BookingModule } from './booking/booking.module';
import { DiagnosticsModule } from './diagnostics/diagnostics.module';
import { DispatchModule } from './dispatch/dispatch.module';
import { DocumentsModule } from './documents/documents.module';
import { DriverModule } from './driver/driver.module';
import { NotificationsModule } from './notifications/notifications.module';
import { ObservabilityModule } from './observability/observability.module';
import { PaymentsModule } from './payments/payments.module';
import { SafetyModule } from './safety/safety.module';
import { RatingsModule } from './ratings/ratings.module';
import { SchedulingModule } from './scheduling/scheduling.module';
import { AuthModule } from './identity/auth.module';
import { UsersModule } from './users/users.module';
import { ZonesModule } from './zones/zones.module';
import { PlacesModule } from './places/places.module';
import { LocationModule } from './location/location.module';
import { RoutesModule } from './routes/routes.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [configuration] }),
    DatabaseModule,
    PersistenceModule,
    HealthModule,
    AuthModule,
    BookingModule,
    DiagnosticsModule,
    DispatchModule,
    DocumentsModule,
    DriverModule,
    NotificationsModule,
    ObservabilityModule,
    PaymentsModule,
    RatingsModule,
    SafetyModule,
    SchedulingModule,
    UsersModule,
    ZonesModule,
    PlacesModule,
    LocationModule,
    RoutesModule,
  ],
})
export class AppModule {}
