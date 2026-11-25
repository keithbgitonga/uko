import { Type } from 'class-transformer';
import { IsIn, IsISO8601, IsObject, IsOptional, ValidateNested } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { StopDto } from '../../booking/dto/quote-request.dto';

export class ScheduleRideDto {
  @ApiProperty({ type: StopDto })
  @IsObject()
  @ValidateNested()
  @Type(() => StopDto)
  pickup: StopDto;

  @ApiProperty({ type: StopDto })
  @IsObject()
  @ValidateNested()
  @Type(() => StopDto)
  dropoff: StopDto;

  @ApiProperty({ example: '2026-11-23T07:30:00.000Z', description: 'ISO-8601, 45 min–90 days ahead' })
  @IsISO8601()
  scheduledAt: string;

  @ApiProperty({ example: 'mpesa', enum: ['mpesa', 'cash'], required: false })
  @IsOptional()
  @IsIn(['mpesa', 'cash'])
  paymentMethod?: 'mpesa' | 'cash';
}
