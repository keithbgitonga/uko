import { Body, Controller, Get, Headers, Post } from '@nestjs/common';
import { IsOptional, IsString } from 'class-validator';
import { AuthService } from '../identity/auth.service';
import { DiagnosticsService } from './diagnostics.service';

export class ClientErrorDto {
  @IsString()
  app!: string;

  @IsString()
  message!: string;

  @IsOptional()
  @IsString()
  version?: string;

  @IsOptional()
  @IsString()
  platform?: string;

  @IsOptional()
  @IsString()
  stack?: string;
}

@Controller('diagnostics')
export class DiagnosticsController {
  constructor(private readonly diagnostics: DiagnosticsService, private readonly auth: AuthService) {}

  @Post('client-errors')
  async report(@Headers('authorization') authHeader: string | undefined, @Body() dto: ClientErrorDto) {
    let userId: string | undefined;
    if (authHeader?.startsWith('Bearer ')) {
      try {
        userId = (await this.auth.verifyAccess(authHeader.slice('Bearer '.length))).id;
      } catch {
        userId = undefined;
      }
    }
    return this.diagnostics.record({ ...dto, userId });
  }

  @Get('client-errors')
  async list() {
    return { errors: await this.diagnostics.recent(100) };
  }
}
