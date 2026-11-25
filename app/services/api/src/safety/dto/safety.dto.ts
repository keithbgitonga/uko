import { IsNumber, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class AddContactDto {
  @ApiProperty({ example: 'Jane W.' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiProperty({ example: '+254712345679' })
  @IsString()
  @Matches(/^\+[1-9]\d{6,14}$/, { message: 'phone must be E.164, e.g. +254712345679' })
  phone: string;

  @ApiProperty({ example: 'Sister', required: false })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  relationship?: string;
}

export class TriggerSosDto {
  @ApiProperty({ example: 'r_…', required: false })
  @IsOptional()
  @IsString()
  rideId?: string;

  @ApiProperty({ example: -1.2921, required: false })
  @IsOptional()
  @IsNumber()
  lat?: number;

  @ApiProperty({ example: 36.8219, required: false })
  @IsOptional()
  @IsNumber()
  lng?: number;

  @ApiProperty({ example: 'Driver took a different route', required: false })
  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string;
}
