import { MiddlewareConsumer, Module, NestModule, RequestMethod } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { OtpRateLimitMiddleware } from './rate-limit.middleware';
import { SmsService } from './sms.service';

@Module({
  controllers: [AuthController],
  providers: [AuthService, SmsService],
  exports: [AuthService],
})
export class AuthModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(OtpRateLimitMiddleware).forRoutes({ path: '*', method: RequestMethod.ALL });
  }
}
