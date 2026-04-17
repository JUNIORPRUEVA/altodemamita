import { SetMetadata } from '@nestjs/common';

export const ALLOW_IN_READ_ONLY_KEY = 'allowInReadOnly';
export const AllowInReadOnly = (): MethodDecorator & ClassDecorator =>
  SetMetadata(ALLOW_IN_READ_ONLY_KEY, true);