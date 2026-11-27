import { Controller, Get, Headers, Query, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../identity/auth.service';
import { PlacesService } from './places.service';

@ApiTags('places')
@ApiBearerAuth()
@Controller('places')
export class PlacesController {
  constructor(private readonly places: PlacesService, private readonly auth: AuthService) {}

  @Get('reverse')
  async reverse(
    @Headers('authorization') authHeader: string | undefined,
    @Query('lat') lat?: string,
    @Query('lng') lng?: string,
  ) {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    await this.auth.verifyAccess(authHeader.slice('Bearer '.length));
    const latitude = Number(lat);
    const longitude = Number(lng);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return { place: null };
    }
    return { place: await this.places.reverse(latitude, longitude) };
  }

  @Get('search')
  async search(@Headers('authorization') authHeader: string | undefined, @Query('q') q?: string) {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    await this.auth.verifyAccess(authHeader.slice('Bearer '.length));
    return { places: await this.places.search(q ?? '') };
  }
}
