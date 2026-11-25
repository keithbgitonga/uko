import { BadGatewayException, BadRequestException, Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { BookingService } from '../booking/booking.service';
import { AnalyticsService } from '../observability/analytics.service';
import { PersistenceService } from '../persistence/persistence.service';
import { MpesaClient } from './mpesa.client';

export type PaymentStatus = 'PENDING' | 'SUCCESS' | 'FAILED';

export interface Payment {
  id: string;
  rideId: string;
  riderId: string;
  amount: number;
  currency: 'KES';
  method: 'mpesa' | 'cash';
  status: PaymentStatus;
  checkoutRequestId?: string;
  merchantRequestId?: string;
  customerMessage?: string;
  receipt?: string;
  createdAt: number;
  updatedAt: number;
}

const MPESA_AUTO_SUCCESS_MS = 4000;
const MPESA_AUTO_FAILURE_MS = 25_000;

/**
 * Walking-skeleton payments. M-Pesa STK is simulated: a pending request
 * becomes SUCCESS after a few seconds (or can be forced with /simulate).
 * Real Daraja STK/callback wiring arrives when sandbox credentials exist.
 */
@Injectable()
export class PaymentsService implements OnModuleInit {
  private payments = new Map<string, Payment>();

  constructor(
    private readonly booking: BookingService,
    private readonly persistence: PersistenceService,
    private readonly mpesa: MpesaClient,
    private readonly analytics: AnalyticsService,
  ) {}

  async onModuleInit(): Promise<void> {
    this.payments = await this.persistence.load<Payment>('payment');
  }

  async requestStk(riderId: string, rideId: string): Promise<Payment> {
    const ride = this.booking.getRide(riderId, rideId);
    if (ride.state !== 'COMPLETED') {
      throw new BadRequestException({ code: 'PAY_AFTER_TRIP', message: 'Payment is collected after the trip completes' });
    }
    if (ride.paymentMethod !== 'mpesa') {
      throw new BadRequestException({ code: 'PAYMENT_METHOD_MISMATCH', message: 'This ride is set to cash' });
    }
    const existing = this.latestForRide(riderId, rideId);
    if (existing?.status === 'SUCCESS') return existing;

    const now = Date.now();
    let checkoutRequestId: string;
    let merchantRequestId: string;
    let customerMessage = 'Enter your M-Pesa PIN on your phone to pay for your Uko? ride.';
    if (this.mpesa.provider === 'daraja') {
      try {
        const stk = await this.mpesa.stkPush({
          phone: ride.riderPhone.replace(/^\+/, ''),
          amount: ride.fare,
          accountReference: ride.id,
          description: 'Uko? Boda ride',
        });
        checkoutRequestId = stk.checkoutRequestId;
        merchantRequestId = stk.merchantRequestId;
        customerMessage = stk.customerMessage || customerMessage;
      } catch (err) {
        throw new BadGatewayException({
          code: 'MPESA_UNAVAILABLE',
          message: err instanceof Error ? err.message : 'M-Pesa is unavailable',
        });
      }
    } else {
      checkoutRequestId = `ws_CO_${now}_${randomUUID().slice(0, 8)}`;
      merchantRequestId = `mr_${randomUUID().slice(0, 12)}`;
    }
    const payment: Payment = {
      id: `pay_${randomUUID()}`,
      rideId,
      riderId,
      amount: ride.fare,
      currency: 'KES',
      method: 'mpesa',
      status: 'PENDING',
      checkoutRequestId,
      merchantRequestId,
      customerMessage,
      createdAt: now,
      updatedAt: now,
    };
    this.payments.set(payment.id, payment);
    this.persistence.persist('payment', payment.id, payment);
    this.analytics.record(riderId, 'payment_started', { paymentId: payment.id, method: 'mpesa', amount: payment.amount });
    return payment;
  }

  confirmCash(riderId: string, rideId: string): Payment {
    const ride = this.booking.getRide(riderId, rideId);
    if (ride.state !== 'COMPLETED') {
      throw new BadRequestException({ code: 'PAY_AFTER_TRIP' });
    }
    if (ride.paymentMethod !== 'cash') {
      throw new BadRequestException({ code: 'PAYMENT_METHOD_MISMATCH', message: 'This ride is set to M-Pesa' });
    }
    const existing = this.latestForRide(riderId, rideId);
    if (existing?.status === 'SUCCESS') return existing;
    const now = Date.now();
    const payment: Payment = {
      id: `pay_${randomUUID()}`,
      rideId,
      riderId,
      amount: ride.fare,
      currency: 'KES',
      method: 'cash',
      status: 'SUCCESS',
      receipt: `CASH-${now}`,
      customerMessage: 'Cash payment recorded.',
      createdAt: now,
      updatedAt: now,
    };
    this.payments.set(payment.id, payment);
    this.persistence.persist('payment', payment.id, payment);
    this.analytics.record(riderId, 'payment_confirmed', { paymentId: payment.id, method: 'cash', amount: payment.amount });
    return payment;
  }

  getPayment(riderId: string, paymentId: string): Payment {
    const payment = this.payments.get(paymentId);
    if (!payment || payment.riderId !== riderId) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND' });
    return this.advance(payment);
  }

  allPayments(): Payment[] {
    return [...this.payments.values()].map((p) => this.advance(p));
  }

  latestForRide(riderId: string, rideId: string): Payment | null {
    const list = [...this.payments.values()]
      .filter((p) => p.riderId === riderId && p.rideId === rideId)
      .sort((a, b) => b.createdAt - a.createdAt);
    if (list.length === 0) return null;
    const latest = this.advance(list[0]);
    // The ride may be completed before the app asks; expose an unpaid state explicitly.
    return latest;
  }

  simulate(riderId: string, paymentId: string, result: 'SUCCESS' | 'FAILED'): Payment {
    const payment = this.getPayment(riderId, paymentId);
    payment.status = result;
    payment.updatedAt = Date.now();
    if (result === 'SUCCESS') payment.receipt = `MPESA-${payment.checkoutRequestId?.slice(-8) ?? payment.id.slice(-8)}`;
    this.persistence.persist('payment', payment.id, payment);
    return payment;
  }

  /** Daraja callback: updates the payment matching the checkout request id. */
  handleCallback(payload: any): { ResultCode: number; ResultDesc: string } {
    const callback = payload?.Body?.stkCallback;
    if (!callback?.CheckoutRequestID) return { ResultCode: 0, ResultDesc: 'Ignored' };
    const payment =
      [...this.payments.values()].find((p) => p.checkoutRequestId === callback.CheckoutRequestID && p.status === 'PENDING') ??
      [...this.payments.values()].find((p) => p.checkoutRequestId === callback.CheckoutRequestID);
    if (!payment) return { ResultCode: 0, ResultDesc: 'Unknown payment' };
    const now = Date.now();
    if (Number(callback.ResultCode) === 0) {
      const items: any[] = callback.CallbackMetadata?.Item ?? [];
      const receipt = items.find((i) => i.Name === 'MpesaReceiptNumber')?.Value;
      payment.status = 'SUCCESS';
      payment.receipt = receipt || `MPESA-${callback.CheckoutRequestID.slice(-8)}`;
      payment.customerMessage = callback.ResultDesc || 'Payment received';
    } else {
      payment.status = 'FAILED';
      payment.customerMessage = callback.ResultDesc || 'Payment was not completed';
    }
    payment.updatedAt = now;
    this.persistence.persist('payment', payment.id, payment);
    return { ResultCode: 0, ResultDesc: 'Accepted' };
  }

  private advance(payment: Payment): Payment {
    if (payment.status !== 'PENDING') return payment;
    if (this.mpesa.provider !== 'mock') return payment;
    const age = Date.now() - payment.createdAt;
    if (age >= MPESA_AUTO_SUCCESS_MS) {
      payment.status = 'SUCCESS';
      payment.receipt = `MPESA-${payment.checkoutRequestId?.slice(-8) ?? payment.id.slice(-8)}`;
      payment.updatedAt = Date.now();
      this.persistence.persist('payment', payment.id, payment);
    } else if (age >= MPESA_AUTO_FAILURE_MS) {
      payment.status = 'FAILED';
      payment.updatedAt = Date.now();
      this.persistence.persist('payment', payment.id, payment);
    }
    return payment;
  }
}
