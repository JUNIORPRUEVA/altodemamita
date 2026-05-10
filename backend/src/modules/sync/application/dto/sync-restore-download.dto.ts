import { IsOptional, IsString } from 'class-validator';

export class SyncRestoreDownloadDto {
  @IsOptional()
  @IsString()
  device_id?: string;

  @IsString()
  admin_password!: string;

  @IsString()
  confirmation_text!: string;
}
