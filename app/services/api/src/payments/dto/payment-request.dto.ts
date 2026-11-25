import { IsIn, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class RidePaymentDto {
  @ApiProperty({ example: 'r_…' })
  @IsString()
  rideId: string;
}

export class SimulatePaymentDto {
  @ApiProperty({ example: 'SUCCESS', enum: ['SUCCESS', 'FAILED'] })
  @IsIn(['SUCCESS', 'FAILED'])
  result: 'SUCCESS' | 'FAILED';
}
