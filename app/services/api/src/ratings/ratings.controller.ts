import { Body, Controller, Get, Headers, Param, Post, UnauthorizedException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { AuthService, DevUser } from '../identity/auth.service';
import { RatingsService } from './ratings.service';

export class RateRideDto {
  @IsString()
  rideId!: string;

  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  comment?: string;
}

@ApiTags('ratings')
@ApiBearerAuth()
@Controller('ratings')
export class RatingsController {
  constructor(private readonly ratings: RatingsService, private readonly auth: AuthService) {}

  @Post()
  async rate(@Headers('authorization') authHeader: string | undefined, @Body() dto: RateRideDto) {
    const user = await this.requireUser(authHeader);
    return { rating: await this.ratings.rate(user.id, dto.rideId, dto.rating, dto.comment) };
  }

  @Get('ride/:rideId')
  async forRide(@Headers('authorization') authHeader: string | undefined, @Param('rideId') rideId: string) {
    const user = await this.requireUser(authHeader);
    return { rating: await this.ratings.forRide(user.id, rideId) };
  }

  @Get('driver/:driverId')
  async driverSummary(@Headers('authorization') authHeader: string | undefined, @Param('driverId') driverId: string) {
    await this.requireUser(authHeader);
    return await this.ratings.driverSummary(driverId);
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
