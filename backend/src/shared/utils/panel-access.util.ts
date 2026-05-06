import { ForbiddenException } from '@nestjs/common';
import { RoleCode } from '@prisma/client';

import { AuthenticatedUser } from '../decorators/current-user.decorator';

const panelRoles = new Set<string>([RoleCode.PANEL_ADMIN, RoleCode.PANEL_VIEWER]);

export function isPanelActor(user: Pick<AuthenticatedUser, 'type' | 'roles'>): boolean {
  return (
    user.type === 'panel' ||
    user.type === 'pwa' ||
    user.roles.some((role) => panelRoles.has(role))
  );
}

export function assertOperationalAccess(
  user: Pick<AuthenticatedUser, 'type' | 'roles'>,
  operationName: string,
): void {
  if (!isPanelActor(user)) {
    return;
  }

  throw new ForbiddenException(
    `${operationName} no esta disponible para clientes panel administrativos.`,
  );
}