import { Type } from 'class-transformer';
import { IsNumber, IsObject, IsOptional, IsString, ValidateNested } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class StopDto {
  @ApiProperty({ example: -1.2921 })
  @IsNumber()
  lat: number;

  @ApiProperty({ example: 36.8219 })
  @IsNumber()
  lng: number;

  @ApiProperty({ example: 'Kenyatta Avenue' })
  @IsString()
  address: string;
}

export class QuoteRequestDto {
  @ApiProperty({ example: '+254712345678', description: 'Optional; defaults to the signed-in rider' })
  @IsOptional()
  @IsString()
  phone?: string;

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
}
