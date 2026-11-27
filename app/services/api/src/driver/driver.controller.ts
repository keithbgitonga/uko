import { BadRequestException, Body, Controller, Get, Headers, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService, DevUser } from '../identity/auth.service';
import { DriverService } from './driver.service';
import { LocationService } from '../location/location.service';
import { SetOnlineDto } from './dto/set-online.dto';

@ApiTags('driver')
@ApiBearerAuth()
@Controller('driver')
export class DriverController {
  constructor(
    private readonly driver: DriverService,
    private readonly auth: AuthService,
    private readonly locations: LocationService,
  ) {}

  @Get('status')
  async status(@Headers('authorization') authHeader?: string) {
    return this.driver.status((await this.requireUser(authHeader)).id);
  }

  @Post('online')
  async setOnline(@Headers('authorization') authHeader: string | undefined, @Body() dto: SetOnlineDto) {
    return this.driver.setOnline((await this.requireUser(authHeader)).id, dto.online);
  }

  @Get('offers')
  async offers(@Headers('authorization') authHeader?: string) {
    const user = (await this.requireUser(authHeader));
    return { offers: this.driver.offersFor(user.id) };
  }

  @Post('offers/:id/accept')
  async accept(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const user = (await this.requireUser(authHeader));
    return { trip: this.driver.acceptOffer(user.id, id) };
  }

  @Post('offers/:id/reject')
  async reject(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const user = (await this.requireUser(authHeader));
    return this.driver.rejectOffer(user.id, id);
  }

  @Post('location')
  async location(
    @Headers('authorization') authHeader: string | undefined,
    @Body() body: { lat?: number; lng?: number },
  ) {
    const user = await this.requireUser(authHeader);
    const lat = Number(body?.lat);
    const lng = Number(body?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new BadRequestException({ code: 'INVALID_LOCATION' });
    }
    return { location: this.locations.set(user.id, lat, lng) };
  }

  @Get('shift')
  async shift(@Headers('authorization') authHeader?: string) {
    return this.driver.shiftSummary((await this.requireUser(authHeader)).id);
  }

  @Get('earnings')
  async earnings(@Headers('authorization') authHeader?: string) {
    return this.driver.earnings((await this.requireUser(authHeader)).id);
  }

  @Get('trips/current')
  async currentTrip(@Headers('authorization') authHeader?: string) {
    return { trip: this.driver.currentTrip((await this.requireUser(authHeader)).id) };
  }

  @Get('trips/:id')
  async getTrip(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { trip: this.driver.getTrip((await this.requireUser(authHeader)).id, id) };
  }

  @Post('trips/:id/arrived')
  async arrived(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { trip: this.driver.advanceTrip((await this.requireUser(authHeader)).id, id, 'arrived') };
  }

  @Post('trips/:id/start')
  async start(
    @Headers('authorization') authHeader: string | undefined,
    @Param('id') id: string,
    @Body() body: { pickupCode?: string },
  ) {
    return { trip: this.driver.advanceTrip((await this.requireUser(authHeader)).id, id, 'start', body?.pickupCode) };
  }

  @Post('trips/:id/cancel')
  async cancel(
    @Headers('authorization') authHeader: string | undefined,
    @Param('id') id: string,
    @Body() body: { reason?: string },
  ) {
    return { trip: this.driver.cancelTrip((await this.requireUser(authHeader)).id, id, body?.reason) };
  }

  @Post('trips/:id/complete')
  async complete(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { trip: this.driver.advanceTrip((await this.requireUser(authHeader)).id, id, 'complete') };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
