import { IsIn } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class UpdateSeriesDto {
  @ApiProperty({ example: 'PAUSED', enum: ['ACTIVE', 'PAUSED', 'CANCELLED'] })
  @IsIn(['ACTIVE', 'PAUSED', 'CANCELLED'])
  status: 'ACTIVE' | 'PAUSED' | 'CANCELLED';
}
