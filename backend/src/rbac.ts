import type { NextFunction, Request, Response } from 'express';
import { prisma } from './prisma';

export const permissionDomains = [
  'clients',
  'lots',
  'products',
  'sellers',
  'sales',
  'payments',
  'installments',
  'users',
  'configuration',
  'reports',
  'auth',
] as const;

const aliases: Record<string, string> = {
  products: 'lots',
};

export function requirePermission(module: string, action: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: { message: 'No autenticado.' } });
    }
    if (await hasPermission(req.user.id, req.user.role, module, action)) {
      return next();
    }
    return res.status(403).json({
      error: {
        code: 'PERMISSION_DENIED',
        message: 'No tienes permiso para realizar esta operacion.',
      },
    });
  };
}

export async function hasPermission(
  userId: string,
  role: 'OWNER' | 'TECH',
  module: string,
  action: string,
) {
  if (role === 'OWNER') return true;
  const normalizedModule = aliases[module] ?? module;
  const direct = await prisma.permission.findFirst({
    where: {
      userId,
      deletedAt: null,
      module: normalizedModule,
    },
  });
  if (permissionAllows(direct?.actions, action)) return true;

  const assignments = await prisma.businessUserRole.findMany({
    where: { userId, deletedAt: null },
    select: { roleId: true },
  });
  if (assignments.length === 0) return false;

  const rolePermission = await prisma.businessRolePermission.findFirst({
    where: {
      roleId: { in: assignments.map((item) => item.roleId) },
      deletedAt: null,
      permission: { module: normalizedModule, deletedAt: null },
    },
    include: { permission: true },
  });
  return permissionAllows(rolePermission?.permission.actions, action);
}

export async function permissionSnapshot(userId: string) {
  const direct = await prisma.permission.findMany({
    where: { userId, deletedAt: null },
    select: { module: true, actions: true },
    orderBy: { module: 'asc' },
  });
  const assignedRoles = await prisma.businessUserRole.findMany({
    where: { userId, deletedAt: null },
    include: {
      role: true,
    },
  });
  return {
    direct: direct.map((item) => ({ module: item.module, actions: actionsArray(item.actions) })),
    roles: assignedRoles.map((item) => ({
      id: item.role.id,
      code: item.role.code,
      name: item.role.name,
    })),
  };
}

function permissionAllows(actions: unknown, action: string) {
  const values = actionsArray(actions);
  return values.includes('*') || values.includes(action);
}

function actionsArray(actions: unknown) {
  return Array.isArray(actions) ? actions.map(String) : [];
}
