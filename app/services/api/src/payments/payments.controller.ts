import { Body, Controller, Get, Headers, Param, Post, Query, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService, DevUser } from '../identity/auth.service';
import { RidePaymentDto, SimulatePaymentDto } from './dto/payment-request.dto';
import { PaymentsService } from './payments.service';

@ApiTags('payments')
@ApiBearerAuth()
@Controller('payments')
export class PaymentsController {
  constructor(
    private readonly payments: PaymentsService,
    private readonly auth: AuthService,
    private readonly config: ConfigService,
  ) {}

  @Post('mpesa/stk')
  async requestStk(@Headers('authorization') authHeader: string | undefined, @Body() dto: RidePaymentDto) {
    return { payment: await this.payments.requestStk((await this.requireUser(authHeader)).id, dto.rideId) };
  }

  @Post('cash/confirm')
  async confirmCash(@Headers('authorization') authHeader: string | undefined, @Body() dto: RidePaymentDto) {
    return { payment: this.payments.confirmCash((await this.requireUser(authHeader)).id, dto.rideId) };
  }

  /** Daraja callback. Public endpoint guarded by an optional shared secret. */
  @Post('mpesa/callback')
  mpesaCallback(@Query('secret') secret: string | undefined, @Body() payload: any) {
    const expected = this.config.get<string>('mpesa.callbackSecret');
    if (expected && secret !== expected) {
      throw new UnauthorizedException({ code: 'CALLBACK_SECRET_INVALID' });
    }
    return this.payments.handleCallback(payload);
  }

  @Get('ride/:rideId')
  async forRide(@Headers('authorization') authHeader: string | undefined, @Param('rideId') rideId: string) {
    return { payment: this.payments.latestForRide((await this.requireUser(authHeader)).id, rideId) };
  }

  @Get(':id')
  async getPayment(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    return { payment: this.payments.getPayment((await this.requireUser(authHeader)).id, id) };
  }

  @Post(':id/simulate')
  async simulate(
    @Headers('authorization') authHeader: string | undefined,
    @Param('id') id: string,
    @Body() dto: SimulatePaymentDto,
  ) {
    return { payment: this.payments.simulate((await this.requireUser(authHeader)).id, id, dto.result) };
  }

  private async requireUser(authHeader?: string): Promise<DevUser> {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    return this.auth.verifyAccess(authHeader.slice('Bearer '.length));
  }
}
