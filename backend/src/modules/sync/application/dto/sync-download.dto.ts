import { IsDateString, IsOptional, IsString } from 'class-validator';

export class SyncDownloadDto {
  @IsOptional()
  @IsString()
  device_id?: string;

  @IsOptional()
  @IsDateString()
  updatedSince?: string;

  @IsOptional()
  @IsString()
  scope_cursors?: string;
}