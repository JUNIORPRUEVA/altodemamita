import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export type AuthClientType = 'desktop' | 'panel' | 'pwa';

export interface AuthenticatedUser {
  sub: string;
  email: string;
  username: string;
  fullName: string;
  isActive: boolean;
  type: AuthClientType;
  roles: string[];
  permissions: string[];
}

export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedUser => {
    const request = context.switchToHttp().getRequest<{ user: AuthenticatedUser }>();
    return request.user;
  },
);