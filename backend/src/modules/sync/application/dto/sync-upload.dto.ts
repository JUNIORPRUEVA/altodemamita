import { Type } from 'class-transformer';
import { IsArray, IsObject, IsOptional, IsString, ValidateNested } from 'class-validator';

export class SyncRecordsDto {
  @IsOptional()
  @IsArray()
  users?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  clients?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  products?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  sellers?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  sales?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  installments?: Record<string, unknown>[];

  @IsOptional()
  @IsArray()
  payments?: Record<string, unknown>[];
}

export class SyncUploadDto {
  @IsOptional()
  @IsString()
  device_id?: string;

  @IsObject()
  @ValidateNested()
  @Type(() => SyncRecordsDto)
  records!: SyncRecordsDto;
}