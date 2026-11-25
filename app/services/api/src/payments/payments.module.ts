import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { AuthModule } from '../identity/auth.module';
import { PaymentsController } from './payments.controller';
import { MpesaClient } from './mpesa.client';
import { PaymentsService } from './payments.service';

@Module({
  imports: [AuthModule, BookingModule],
  controllers: [PaymentsController],
  providers: [PaymentsService, MpesaClient],
  exports: [PaymentsService],
})
export class PaymentsModule {}
