import { IsOptional, IsString } from 'class-validator';

/**
 * Accepts both snake_case (device_id) sent by the PWA and camelCase (deviceId)
 * for robustness against copy-paste or future client changes.
 */
export class ActivateDeviceDto {
  @IsOptional()
  @IsString()
  device_id?: string;

  /** camelCase alias – accepted alongside device_id */
  @IsOptional()
  @IsString()
  deviceId?: string;

  @IsOptional()
  @IsString()
  device_name?: string;

  @IsOptional()
  @IsString()
  platform?: string;

  /** Returns the resolved device ID, preferring device_id over deviceId. */
  get resolvedDeviceId(): string {
    return (this.device_id ?? this.deviceId ?? '').trim();
  }
}
