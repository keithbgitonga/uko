import { Body, Controller, ForbiddenException, Get, Headers, Param, Post, Query, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { BookingService } from '../booking/booking.service';
import { DriverService } from '../driver/driver.service';
import { DocumentsService } from '../documents/documents.service';
import { AuthService } from '../identity/auth.service';
import { PaymentsService } from '../payments/payments.service';
import { AuditService } from './audit.service';
import { SafetyService } from '../safety/safety.service';
import { SchedulingService } from '../scheduling/scheduling.service';

@ApiTags('dispatch')
@ApiBearerAuth()
@Controller('dispatch')
export class DispatchController {
  constructor(
    private readonly booking: BookingService,
    private readonly driver: DriverService,
    private readonly safety: SafetyService,
    private readonly scheduling: SchedulingService,
    private readonly auth: AuthService,
    private readonly audit: AuditService,
    private readonly documents: DocumentsService,
    private readonly payments: PaymentsService,
    private readonly config: ConfigService,
  ) {}

  @Get('overview')
  async overview(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    const rides = this.booking.allRides();
    const incidents = this.safety.allIncidents();
    const scheduled = this.scheduling.allScheduledRides();
    const nairobiToday = nairobiDate(new Date().toISOString());
    const completedToday = rides.filter(
      (r) => r.state === 'COMPLETED' && nairobiDate(r.createdAt) === nairobiToday,
    );
    return {
      metrics: {
        activeRides: rides.filter((r) => ['SEARCHING', 'ASSIGNED', 'ARRIVING', 'ARRIVED', 'IN_PROGRESS'].includes(r.state)).length,
        completedToday: completedToday.length,
        grossToday: completedToday.reduce((sum, r) => sum + r.fare, 0),
        openIncidents: incidents.filter((i) => ['OPEN', 'ACKED'].includes(i.state)).length,
        driversOnline: this.driver.onlineDriverCount(),
        scheduledUpcoming: scheduled.filter((s) => s.status === 'SCHEDULED').length,
      },
      rides: rides.slice(0, 8),
      incidents: incidents.slice(0, 8),
    };
  }

  @Get('rides')
  async rides(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    return { rides: this.booking.allRides() };
  }

  @Post('rides/:id/cancel')
  async cancelRide(
    @Headers('authorization') authHeader: string | undefined,
    @Param('id') id: string,
    @Body() body: { reason?: string; note?: string },
  ) {
    const actor = await this.requireOps(authHeader);
    const ride = this.booking.cancelRideByOps(id, body?.reason, body?.note);
    this.audit.record(actor, 'ride.cancel', 'ride', id, { fare: ride.fare, reason: ride.cancellation?.label, by: 'dispatch' });
    return { ride };
  }

  @Get('incidents')
  async incidents(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    return { incidents: this.safety.allIncidents() };
  }

  @Post('incidents/:id/resolve')
  async resolveIncident(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const actor = await this.requireOps(authHeader);
    const incident = this.safety.resolveIncident(id);
    this.audit.record(actor, 'incident.resolve', 'incident', id, { state: incident.state });
    return { incident };
  }

  @Get('reconciliation')
  async reconciliation(@Headers('authorization') authHeader: string | undefined, @Query('date') requestedDate?: string) {
    await this.requireOps(authHeader);
    const date = requestedDate || nairobiDate(new Date().toISOString());
    const rides = this.booking.allRides().filter((r) => r.state === 'COMPLETED' && nairobiDate(r.createdAt) === date);
    const payments = this.payments.allPayments();
    const byMethod: Record<string, { rides: number; paid: number; amount: number }> = {};
    const mismatches: any[] = [];
    let paidAmount = 0;
    let paidCount = 0;
    for (const ride of rides) {
      const ridePayments = payments.filter((p) => p.rideId === ride.id);
      const successful = ridePayments.filter((p) => p.status === 'SUCCESS');
      const latest = ridePayments.sort((a, b) => b.createdAt - a.createdAt)[0];
      const method = ride.paymentMethod;
      byMethod[method] = byMethod[method] ?? { rides: 0, paid: 0, amount: 0 };
      byMethod[method].rides += 1;
      if (successful.length > 0) {
        paidCount += 1;
        paidAmount += ride.fare;
        byMethod[method].paid += 1;
        byMethod[method].amount += ride.fare;
      } else {
        mismatches.push({ rideId: ride.id, reason: 'unpaid', fare: ride.fare, paymentStatus: latest?.status ?? 'NONE', method });
      }
      if (successful.length > 1) {
        mismatches.push({ rideId: ride.id, reason: 'duplicate_payment', fare: ride.fare, count: successful.length });
      }
      for (const payment of successful) {
        if (payment.amount !== ride.fare) {
          mismatches.push({ rideId: ride.id, reason: 'amount_mismatch', fare: ride.fare, paymentAmount: payment.amount });
        }
      }
    }
    const grossFare = rides.reduce((sum, r) => sum + r.fare, 0);
    const commissionRate = 20;
    const commission = Math.round((paidAmount * commissionRate) / 100);
    return {
      date,
      currency: 'KES',
      completedRides: rides.length,
      grossFare,
      paidCount,
      paidAmount,
      unpaidCount: rides.length - paidCount,
      unpaidAmount: grossFare - paidAmount,
      byMethod,
      commission: { rate: commissionRate, gross: paidAmount, commission, net: paidAmount - commission },
      mismatches,
    };
  }

  @Get('documents')
  async documentsList(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    return { documents: await this.documents.listAll() };
  }

  @Post('documents/:id/approve')
  async approveDocument(@Headers('authorization') authHeader: string | undefined, @Param('id') id: string) {
    const actor = await this.requireOps(authHeader);
    const document = await this.documents.review(id, actor.id, 'APPROVED');
    this.audit.record(actor, 'document.approve', 'driver_document', id, { type: document.type });
    return { document };
  }

  @Post('documents/:id/reject')
  async rejectDocument(
    @Headers('authorization') authHeader: string | undefined,
    @Param('id') id: string,
    @Body() body: { reason?: string },
  ) {
    const actor = await this.requireOps(authHeader);
    const document = await this.documents.review(id, actor.id, 'REJECTED', body?.reason);
    this.audit.record(actor, 'document.reject', 'driver_document', id, { type: document.type, reason: body?.reason });
    return { document };
  }

  @Get('audit')
  async auditLog(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    return { entries: await this.audit.list(100) };
  }

  @Get('scheduled')
  async scheduled(@Headers('authorization') authHeader?: string) {
    await this.requireOps(authHeader);
    return { scheduledRides: this.scheduling.allScheduledRides(), series: this.scheduling.allSeries() };
  }

  private async requireOps(authHeader?: string) {
    if (!authHeader?.startsWith('Bearer ')) throw new UnauthorizedException({ code: 'ACCESS_MISSING' });
    const user = await this.auth.verifyAccess(authHeader.slice('Bearer '.length));
    const allowList = this.config.get<string[]>('dispatchPhones') ?? [];
    if (allowList.length > 0 && !allowList.includes(user.phone) && !this.auth.isTestOpsPhone(user.phone)) {
      throw new ForbiddenException({ code: 'DISPATCH_FORBIDDEN', message: 'This account is not allowed to use dispatch' });
    }
    return user;
  }
}

function nairobiDate(iso: string): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return `${get('year')}-${get('month')}-${get('day')}`;
}
