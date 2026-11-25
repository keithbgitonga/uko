import { Controller, Get, Headers, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../identity/auth.service';

@ApiTags('users')
@ApiBearerAuth()
@Controller('me')
export class UsersController {
  constructor(private readonly auth: AuthService) {}

  @Get()
  async me(@Headers('authorization') authHeader?: string) {
    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    }
    return { user: await this.auth.verifyAccess(authHeader.slice('Bearer '.length)) };
  }
}
