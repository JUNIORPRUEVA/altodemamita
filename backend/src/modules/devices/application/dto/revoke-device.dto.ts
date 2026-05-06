import { IsString } from 'class-validator';

export class RevokeDeviceDto {
  @IsString()
  device_id!: string;
}