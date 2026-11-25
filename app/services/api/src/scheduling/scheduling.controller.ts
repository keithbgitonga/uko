import { Body, Controller, Get, Headers, Param, Patch, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService, DevUser } from '../identity/auth.service';
import { ScheduleRideDto } from './dto/schedule-ride.dto';
import { RepeatRideDto } from './dto/repeat-ride.dto';
import { UpdateSeriesDto } from './dto/update-series.dto';
import { SchedulingService } from './scheduling.service';

@ApiTags('scheduling')
@ApiBearerAuth()
@Controller()
export class SchedulingController {
  constructor(private readonly scheduling: SchedulingService, private readonly auth: AuthService) {}

  @Post('scheduled-rides')
  async createRide(@Headers('authorization') authHeader: string | undefined, @Body() dto: ScheduleRideDto) {
    const user = (await this.requireUser(authHeader));
    return {
      scheduledRide: this.scheduling.createRide(
        user.id,
        user.phone,
        dto.pickup,
        dto.dropoff,
        dto.scheduledAt,
        dto.paymentMethod ?? 'mpesa',
      ),
    };
  }

  @Post('scheduling/run-due')
  async runDue(@Headers('authorization') authHeader?: string) {
    await this.requireUser(authHeader);
    return this.scheduling.activateDue();
  }

  @Get('scheduled-rides')
  async listRides(@Headers('authorization') authHeader?: string) {
    return { scheduledRides: this.scheduling.listRides((await this.requireUser(authHeader)).id) };
  }

  @Post('scheduled-rides/:id/cancel')
  async cancelRide(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { scheduledRide: this.scheduling.cancelRide((await this.requireUser(authHeader)).id, id) };
  }

  @Post('scheduled-rides/:id/repeat')
  async repeat(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string, @Body() dto: RepeatRideDto) {
    return { series: this.scheduling.repeatRide((await this.requireUser(authHeader)).id, id, dto.weekdays, dto.endDate) };
  }

  @Get('schedule-series')
  async listSeries(@Headers('authorization') authHeader?: string) {
    return { series: this.scheduling.listSeries((await this.requireUser(authHeader)).id) };
  }

  @Patch('schedule-series/:id')
  async updateSeries(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string, @Body() dto: UpdateSeriesDto) {
    return { series: this.scheduling.updateSeries((await this.requireUser(authHeader)).id, id, dto.status) };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
