import { IsIn, IsString } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateRideDto {
  @ApiProperty({ example: 'q_xxx' })
  @IsString()
  quoteId: string;

  @ApiProperty({ example: 'mpesa', enum: ['mpesa', 'cash'] })
  @IsIn(['mpesa', 'cash'])
  paymentMethod: 'mpesa' | 'cash';
}
