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

  /** Optional aliases accepted from clients */
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  deviceName?: string;

  @IsOptional()
  @IsString()
  platform?: string;

  /** Returns the resolved device ID, preferring device_id over deviceId. */
  get resolvedDeviceId(): string {
    return (this.device_id ?? this.deviceId ?? '').trim();
  }

  /** Returns normalized device name from any accepted key. */
  get resolvedDeviceName(): string | undefined {
    const value = (this.device_name ?? this.name ?? this.deviceName ?? '').trim();
    return value.length > 0 ? value : undefined;
  }
}
