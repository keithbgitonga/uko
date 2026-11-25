import { IsBoolean } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SetOnlineDto {
  @ApiProperty({ example: true })
  @IsBoolean()
  online: boolean;
}
