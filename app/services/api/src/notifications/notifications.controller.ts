import { Body, Controller, Get, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsIn, IsString } from 'class-validator';
import { AuthService, DevUser } from '../identity/auth.service';
import { NotificationsService } from './notifications.service';

export class RegisterDeviceDto {
  @IsString()
  token!: string;

  @IsIn(['android', 'ios'])
  platform: 'android' | 'ios' = 'android';
}

@ApiTags('notifications')
@ApiBearerAuth()
@Controller('notifications')
export class NotificationsController {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly auth: AuthService,
  ) {}

  @Post('devices')
  async register(@Headers('authorization') authHeader: string | undefined, @Body() dto: RegisterDeviceDto) {
    const user = await this.requireUser(authHeader);
    return { device: await this.notifications.registerDevice(user.id, dto.token, dto.platform) };
  }

  @Get('devices')
  async devices(@Headers('authorization') authHeader: string | undefined) {
    return { devices: await this.notifications.devices((await this.requireUser(authHeader)).id) };
  }

  @Get()
  async list(@Headers('authorization') authHeader: string | undefined) {
    return { notifications: await this.notifications.list((await this.requireUser(authHeader)).id) };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
