import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { RoleCode } from '@prisma/client';
import { Reflector } from '@nestjs/core';

import { PERMISSIONS_KEY } from '../decorators/permissions.decorator';

const privilegedRoles = new Set<string>([
  RoleCode.SUPER_ADMIN,
  RoleCode.ADMIN,
  RoleCode.PANEL_ADMIN,
]);

const privilegedPermissions = new Set<string>([
  'auth.manage',
  'system.config',
  'users.write',
]);

@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredPermissions = this.reflector.getAllAndOverride<string[]>(PERMISSIONS_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!requiredPermissions || requiredPermissions.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest<{
      user?: { permissions?: string[]; roles?: string[] };
    }>();
    const roles = request.user?.roles ?? [];
    const permissions = request.user?.permissions ?? [];

    if (roles.some((role) => privilegedRoles.has(role))) {
      return true;
    }
    if (permissions.some((permission) => privilegedPermissions.has(permission))) {
      return true;
    }

    const hasAll = requiredPermissions.every((permission) => permissions.includes(permission));

    if (!hasAll) {
      throw new ForbiddenException('No tiene permisos suficientes para esta operación.');
    }

    return true;
  }
}