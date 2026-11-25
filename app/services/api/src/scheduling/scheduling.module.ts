import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { AuthModule } from '../identity/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { SchedulingController } from './scheduling.controller';
import { SchedulingService } from './scheduling.service';

@Module({
  imports: [AuthModule, BookingModule, NotificationsModule],
  controllers: [SchedulingController],
  providers: [SchedulingService],
  exports: [SchedulingService],
})
export class SchedulingModule {}
