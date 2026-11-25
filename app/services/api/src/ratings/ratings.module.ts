import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { AuthModule } from '../identity/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { RatingsController } from './ratings.controller';
import { RatingsService } from './ratings.service';

@Module({
  imports: [AuthModule, BookingModule, NotificationsModule],
  controllers: [RatingsController],
  providers: [RatingsService],
})
export class RatingsModule {}
