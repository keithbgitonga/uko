import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { DocumentsModule } from '../documents/documents.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { AuthModule } from '../identity/auth.module';
import { DriverController } from './driver.controller';
import { DriverService } from './driver.service';

@Module({
  imports: [AuthModule, BookingModule, NotificationsModule, DocumentsModule],
  controllers: [DriverController],
  providers: [DriverService],
  exports: [DriverService],
})
export class DriverModule {}
