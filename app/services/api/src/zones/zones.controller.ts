import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';

/** Walking-skeleton zone config. Sprint 1 replaces this with Postgres reads. */
const THIKA_ZONE = {
  id: 'zone_thika_pilot',
  name: 'Thika pilot zone',
  city: 'Thika',
  currency: 'KES',
  category: 'boda',
  pricing: {
    baseFare: 50,
    perKm: 25,
    perMinute: 3,
    minimumFare: 80,
    cancellationFee: 0,
    commissionPercent: 20,
    surge: { enabled: false },
  },
};

@ApiTags('zones')
@Controller('zones')
export class ZonesController {
  @Get()
  list() {
    return { zones: [THIKA_ZONE] };
  }

  @Get('active')
  active() {
    return THIKA_ZONE;
  }
}
