import { IsOptional, IsString } from 'class-validator';

export class ActivateDeviceDto {
  @IsString()
  device_id!: string;

  @IsOptional()
  @IsString()
  device_name?: string;

  @IsOptional()
  @IsString()
  platform?: string;
}
