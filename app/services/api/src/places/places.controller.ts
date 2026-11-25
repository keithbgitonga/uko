import { Controller, Get, Headers, Query, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../identity/auth.service';
import { PlacesService } from './places.service';

@ApiTags('places')
@ApiBearerAuth()
@Controller('places')
export class PlacesController {
  constructor(private readonly places: PlacesService, private readonly auth: AuthService) {}

  @Get('search')
  async search(@Headers('authorization') authHeader: string | undefined, @Query('q') q?: string) {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    await this.auth.verifyAccess(authHeader.slice('Bearer '.length));
    return { places: await this.places.search(q ?? '') };
  }
}
