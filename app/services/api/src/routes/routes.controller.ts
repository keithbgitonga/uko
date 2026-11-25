import { BadRequestException, Controller, Get, Headers, Query, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../identity/auth.service';
import { RoutesService } from './routes.service';

@ApiTags('routes')
@ApiBearerAuth()
@Controller('routes')
export class RoutesController {
  constructor(private readonly routes: RoutesService, private readonly auth: AuthService) {}

  @Get()
  async route(
    @Headers('authorization') authHeader: string | undefined,
    @Query('pickupLat') pickupLat: string,
    @Query('pickupLng') pickupLng: string,
    @Query('dropoffLat') dropoffLat: string,
    @Query('dropoffLng') dropoffLng: string,
  ) {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    await this.auth.verifyAccess(authHeader.slice('Bearer '.length));
    const values = [pickupLat, pickupLng, dropoffLat, dropoffLng].map(Number);
    if (values.some((v) => !Number.isFinite(v)) || Math.abs(values[0]) > 90 || Math.abs(values[2]) > 90) {
      throw new BadRequestException({ code: 'INVALID_COORDINATES' });
    }
    return { route: await this.routes.route(values[0], values[1], values[2], values[3]) };
  }
}
