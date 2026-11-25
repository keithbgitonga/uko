import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { DatabaseService } from '../database/database.service';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly db: DatabaseService) {}

  @Get()
  health() {
    return {
      status: 'ok',
      service: 'uko-api',
      version: '0.1.0',
      time: new Date().toISOString(),
    };
  }

  @Get('db')
  async dbHealth() {
    return { database: (await this.db.ping()) ? 'up' : 'down' };
  }
}
