import { IsString, Matches } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class OtpRequestDto {
  @ApiProperty({ example: '+254712345678', description: 'E.164 phone number' })
  @IsString()
  @Matches(/^\+[1-9]\d{6,14}$/, { message: 'phone must be E.164, e.g. +254712345678' })
  phone: string;
}
