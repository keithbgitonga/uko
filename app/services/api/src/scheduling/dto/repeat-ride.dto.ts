import { ArrayMaxSize, ArrayMinSize, IsArray, IsISO8601, IsInt, Max, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class RepeatRideDto {
  @ApiProperty({ example: [1, 3, 5], description: 'ISO weekdays: 1=Mon … 7=Sun' })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(7)
  @IsInt({ each: true })
  @Min(1, { each: true })
  @Max(7, { each: true })
  weekdays: number[];

  @ApiProperty({ example: '2026-12-20T00:00:00.000Z', description: 'Series end date (max 8 weeks)' })
  @IsISO8601()
  endDate: string;
}
