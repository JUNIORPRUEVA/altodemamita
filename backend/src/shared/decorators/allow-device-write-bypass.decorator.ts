import { SetMetadata } from '@nestjs/common';

export const ALLOW_DEVICE_WRITE_BYPASS_KEY = 'allowDeviceWriteBypass';
export const AllowDeviceWriteBypass = (): MethodDecorator & ClassDecorator =>
  SetMetadata(ALLOW_DEVICE_WRITE_BYPASS_KEY, true);