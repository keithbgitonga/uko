import { Body, Controller, Get, Headers, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService, DevUser } from '../identity/auth.service';
import { BookingService } from './booking.service';
import { LocationService } from '../location/location.service';
import { CreateRideDto } from './dto/create-ride.dto';
import { QuoteRequestDto } from './dto/quote-request.dto';

@ApiTags('booking')
@ApiBearerAuth()
@Controller()
export class BookingController {
  constructor(
    private readonly booking: BookingService,
    private readonly auth: AuthService,
    private readonly locations: LocationService,
  ) {}

  @Post('quotes')
  async quote(@Headers('authorization') authHeader: string | undefined, @Body() dto: QuoteRequestDto) {
    const user = (await this.requireUser(authHeader));
    return { quote: await this.booking.createQuote(user.id, user.phone, dto.pickup, dto.dropoff) };
  }

  @Post('rides')
  async createRide(@Headers('authorization') authHeader: string | undefined, @Body() dto: CreateRideDto) {
    const user = (await this.requireUser(authHeader));
    return { ride: this.booking.createRide(user.id, dto.quoteId, dto.paymentMethod) };
  }

  @Get('rides/:id')
  async getRide(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const user = (await this.requireUser(authHeader));
    return { ride: this.booking.getRide(user.id, id) };
  }

  @Get('rides/:id/driver-location')
  async driverLocation(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const user = await this.requireUser(authHeader);
    const ride = this.booking.getRide(user.id, id);
    return { location: this.locations.get(ride.driver?.driverId) };
  }

  @Get('rides')
  async listRides(@Headers('authorization') authHeader: string | undefined) {
    const user = (await this.requireUser(authHeader));
    return { rides: this.booking.listRides(user.id) };
  }

  @Post('rides/:id/cancel')
  async cancelRide(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const user = (await this.requireUser(authHeader));
    return { ride: this.booking.cancelRide(user.id, id) };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
