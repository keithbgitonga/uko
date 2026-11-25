import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { DocumentsModule } from '../documents/documents.module';
import { DriverModule } from '../driver/driver.module';
import { AuthModule } from '../identity/auth.module';
import { PaymentsModule } from '../payments/payments.module';
import { SafetyModule } from '../safety/safety.module';
import { SchedulingModule } from '../scheduling/scheduling.module';
import { AuditService } from './audit.service';
import { DispatchController } from './dispatch.controller';

@Module({
  imports: [AuthModule, BookingModule, DriverModule, DocumentsModule, PaymentsModule, SafetyModule, SchedulingModule],
  controllers: [DispatchController],
  providers: [AuditService],
})
export class DispatchModule {}
