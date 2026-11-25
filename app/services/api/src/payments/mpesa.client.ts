import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface StkPushResult {
  merchantRequestId: string;
  checkoutRequestId: string;
  customerMessage: string;
}

/**
 * Daraja (M-Pesa) STK client. `MPESA_PROVIDER=mock` keeps the walking-skeleton
 * simulator; `daraja` calls the real sandbox/production endpoints with OAuth.
 */
@Injectable()
export class MpesaClient {
  private readonly logger = new Logger(MpesaClient.name);
  private token?: { value: string; expiresAt: number };

  constructor(private readonly config: ConfigService) {}

  get provider(): 'mock' | 'daraja' {
    return this.config.get<string>('mpesa.provider') === 'daraja' ? 'daraja' : 'mock';
  }

  async stkPush(input: { phone: string; amount: number; accountReference: string; description: string }): Promise<StkPushResult> {
    const token = await this.accessToken();
    const shortcode = this.config.get<string>('mpesa.shortcode')!;
    const passkey = this.config.get<string>('mpesa.passkey')!;
    const timestamp = darajaTimestamp(new Date());
    const password = Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');
    const response = await fetch(`${this.baseUrl()}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        BusinessShortCode: shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: Math.round(input.amount),
        PartyA: input.phone,
        PartyB: shortcode,
        PhoneNumber: input.phone,
        CallBackURL: this.config.get<string>('mpesa.callbackUrl'),
        AccountReference: input.accountReference,
        TransactionDesc: input.description,
      }),
    });
    const body: any = await response.json().catch(() => ({}));
    if (!response.ok || body.ResponseCode !== '0') {
      this.logger.error(`STK push failed: ${response.status} ${JSON.stringify(body)}`);
      throw new Error(body.errorMessage || body.ResponseDescription || `Daraja HTTP ${response.status}`);
    }
    return {
      merchantRequestId: body.MerchantRequestID,
      checkoutRequestId: body.CheckoutRequestID,
      customerMessage: body.CustomerMessage,
    };
  }

  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now() + 30_000) return this.token.value;
    const key = this.config.get<string>('mpesa.consumerKey');
    const secret = this.config.get<string>('mpesa.consumerSecret');
    const auth = Buffer.from(`${key}:${secret}`).toString('base64');
    const response = await fetch(`${this.baseUrl()}/oauth/v1/generate?grant_type=client_credentials`, {
      headers: { authorization: `Basic ${auth}` },
    });
    const body: any = await response.json().catch(() => ({}));
    if (!response.ok || !body.access_token) {
      throw new Error(`Daraja OAuth failed: HTTP ${response.status}`);
    }
    this.token = { value: body.access_token, expiresAt: Date.now() + (Number(body.expires_in) || 3599) * 1000 };
    return this.token.value;
  }

  private baseUrl(): string {
    return this.config.get<string>('mpesa.baseUrl')!.replace(/\/$/, '');
  }
}

/**
 * EAT timestamp in the YYYYMMDDHHmmss shape Daraja expects.
 */
export function darajaTimestamp(date: Date): string {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).formatToParts(date);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  return `${get('year')}${get('month')}${get('day')}${get('hour')}${get('minute')}${get('second')}`;
}
