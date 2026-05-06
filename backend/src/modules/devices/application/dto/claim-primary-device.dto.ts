import { IsOptional, IsString } from 'class-validator';

export class ClaimPrimaryDeviceDto {
  @IsOptional()
  @IsString()
  device_id?: string;

  @IsOptional()
  @IsString()
  device_name?: string;

  @IsOptional()
  @IsString()
  platform?: string;
}