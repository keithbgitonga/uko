import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * SMS delivery adapter. Defaults to the dev channel (code logged, returned in
 * dev responses). Africa's Talking is wired behind env credentials; the rest
 * of the app only depends on this interface.
 */
@Injectable()
export class SmsService {
  constructor(private readonly config: ConfigService) {}

  async sendOtp(phone: string, code: string): Promise<{ channel: 'sms' | 'dev' }> {
    const provider = this.config.get<string>('sms.provider');
    const username = this.config.get<string>('sms.username');
    const apiKey = this.config.get<string>('sms.apiKey');
    if (provider === 'africastalking' && username && apiKey) {
      const body = new URLSearchParams({
        username,
        to: phone,
        message: `Your Uko? verification code is ${code}. Do not share it.`,
      });
      const senderId = this.config.get<string>('sms.senderId');
      if (senderId) body.set('from', senderId);
      const base = (this.config.get<string>('sms.baseUrl') ?? 'https://api.africastalking.com').replace(/\/$/, '');
      const response = await fetch(`${base}/version1/messaging`, {
        method: 'POST',
        headers: {
          apiKey,
          'content-type': 'application/x-www-form-urlencoded',
          accept: 'application/json',
        },
        body,
      });
      if (!response.ok) throw new Error(`SMS provider returned ${response.status}`);
      return { channel: 'sms' };
    }
    console.log(`[dev-sms] OTP for ${maskPhone(phone)}: ${code}`);
    return { channel: 'dev' };
  }
}

function maskPhone(phone: string): string {
  return phone.length > 6 ? `${phone.slice(0, 4)}****${phone.slice(-3)}` : '****';
}
