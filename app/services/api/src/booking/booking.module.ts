import { Module } from '@nestjs/common';
import { AuthModule } from '../identity/auth.module';
import { BookingController } from './booking.controller';
import { NotificationsModule } from '../notifications/notifications.module';
import { BookingService } from './booking.service';

@Module({
  imports: [AuthModule, NotificationsModule],
  controllers: [BookingController],
  providers: [BookingService],
  exports: [BookingService],
})
export class BookingModule {}
