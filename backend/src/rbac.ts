import type { NextFunction, Request, Response } from 'express';
import { prisma } from './prisma';

/**
 * Capa RBAC canonica.
 *
 * El catalogo del desktop guarda recursos y acciones en espanol
 * (`pagos` / `["ver","crear","editar","eliminar"]`) mientras el backend nombra
 * los recursos en ingles. Toda comparacion de permisos pasa por aqui: no debe
 * existir comparacion ES/EN dispersa por la aplicacion.
 */

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
  'dashboard',
  'search',
  'notifications',
  'auth',
] as const;

export type CanonicalAction =
  | 'read'
  | 'create'
  | 'update'
  | 'delete'
  | 'annul'
  | 'cancel'
  | 'manage';

const resourceAliases: Record<string, string> = {
  products: 'lots',
  solares: 'lots',
  lotes: 'lots',
  clientes: 'clients',
  vendedores: 'sellers',
  ventas: 'sales',
  pagos: 'payments',
  cuotas: 'installments',
  usuarios: 'users',
  configuracion: 'configuration',
  configuracin: 'configuration',
  settings: 'configuration',
  reportes: 'reports',
  resumen: 'dashboard',
  busqueda: 'search',
  backups: 'configuration',
  backup: 'configuration',
  notificaciones: 'notifications',
};

const actionAliases: Record<string, CanonicalAction> = {
  ver: 'read',
  read: 'read',
  consultar: 'read',
  imprimir: 'read',
  crear: 'create',
  create: 'create',
  registrar: 'create',
  registrar_pagos: 'create',
  editar: 'update',
  update: 'update',
  modificar: 'update',
  eliminar: 'delete',
  delete: 'delete',
  borrar: 'delete',
  anular: 'annul',
  annul: 'annul',
  cancelar: 'cancel',
  cancel: 'cancel',
  gestionar: 'manage',
  manage: 'manage',
  administrar: 'manage',
};

/**
 * Acciones heredadas *amplias*. `write` se expande a las mutaciones ordinarias
 * pero NUNCA a `annul`/`cancel`/`manage`: anular un pago no puede quedar
 * habilitado por un permiso generico de escritura.
 */
const legacyExpansions: Record<string, CanonicalAction[]> = {
  write: ['create', 'update', 'delete'],
  '*': ['read', 'create', 'update', 'delete'],
};

export function canonicalPermissionModule(value: string) {
  const normalized = value.trim().toLowerCase();
  return resourceAliases[normalized] ?? normalized;
}

export function canonicalPermissionAction(value: string): CanonicalAction | null {
  const normalized = value.trim().toLowerCase();
  return actionAliases[normalized] ?? null;
}

/** Expande la lista de acciones cruda de una fila a acciones canonicas. */
export function canonicalActions(actions: unknown): Set<CanonicalAction> {
  const result = new Set<CanonicalAction>();
  if (!Array.isArray(actions)) {
    return result;
  }
  for (const raw of actions) {
    const value = String(raw ?? '').trim().toLowerCase();
    if (!value) continue;
    const direct = actionAliases[value];
    if (direct) {
      result.add(direct);
      continue;
    }
    const expansion = legacyExpansions[value];
    if (expansion) {
      for (const action of expansion) {
        result.add(action);
      }
    }
  }
  return result;
}

export type CanonicalPermissionMap = Map<string, Set<CanonicalAction>>;

/**
 * Permisos efectivos del usuario: filas directas + filas heredadas de sus
 * roles, ya normalizadas a recurso/accion canonicos.
 */
export async function canonicalPermissionsFor(
  userId: string,
  role: 'OWNER' | 'TECH',
): Promise<CanonicalPermissionMap> {
  const map: CanonicalPermissionMap = new Map();
  if (role === 'OWNER') {
    return map;
  }

  const merge = (resource: unknown, actions: unknown) => {
    if (typeof resource !== 'string') return;
    const key = canonicalPermissionModule(resource);
    const set = map.get(key) ?? new Set<CanonicalAction>();
    for (const action of canonicalActions(actions)) {
      set.add(action);
    }
    if (set.size > 0) {
      map.set(key, set);
    }
  };

  const direct = await prisma.permission.findMany({
    where: { userId, deletedAt: null },
    select: { module: true, actions: true },
  });
  for (const row of direct) {
    merge(row.module, row.actions);
  }

  const assignments = await prisma.businessUserRole.findMany({
    where: { userId, deletedAt: null },
    select: { roleId: true },
  });
  if (assignments.length > 0) {
    const rolePermissions = await prisma.businessRolePermission.findMany({
      where: { roleId: { in: assignments.map((item) => item.roleId) }, deletedAt: null },
      include: { permission: true },
    });
    for (const row of rolePermissions) {
      merge(row.permission?.module, row.permission?.actions);
    }
  }

  return map;
}

export function mapAllows(
  map: CanonicalPermissionMap,
  resource: string,
  action: CanonicalAction,
) {
  const set = map.get(canonicalPermissionModule(resource));
  return set?.has(action) ?? false;
}

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
  const canonicalAction = canonicalPermissionAction(action);
  if (!canonicalAction) {
    return false;
  }
  if (role === 'OWNER') {
    return true;
  }
  const map = await canonicalPermissionsFor(userId, role);
  return mapAllows(map, module, canonicalAction);
}

export async function hasPaymentCancellationPermission(
  userId: string,
  role: 'OWNER' | 'TECH',
) {
  if (role === 'OWNER') return true;
  const map = await canonicalPermissionsFor(userId, role);
  return mapAllows(map, 'payments', 'annul');
}

/** Compatibilidad: util para tests y chequeos sin acceso a base de datos. */
export function permissionGrantsPaymentCancellation(module: unknown, actions: unknown) {
  if (typeof module !== 'string') return false;
  if (canonicalPermissionModule(module) !== 'payments') return false;
  return canonicalActions(actions).has('annul');
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

/**
 * Codigos de permiso que expone el contrato de autenticacion, p. ej.
 * `payments.annul`. OWNER recibe el catalogo administrativo completo.
 */
export const ownerPermissionCodes = [
  'clients.read',
  'clients.create',
  'clients.update',
  'clients.delete',
  'products.read',
  'products.create',
  'products.update',
  'products.delete',
  'sellers.read',
  'sellers.create',
  'sellers.update',
  'sellers.delete',
  'sales.read',
  'sales.create',
  'sales.update',
  'sales.delete',
  'sales.cancel',
  'payments.read',
  'payments.create',
  'payments.update',
  'payments.annul',
  'installments.read',
  'installments.create',
  'installments.update',
  'users.read',
  'users.create',
  'users.update',
  'users.delete',
  'users.manage',
  'configuration.read',
  'configuration.update',
  'reports.read',
  'sync.manage',
];

export function contractPermissionCodes(
  role: 'OWNER' | 'TECH',
  map: CanonicalPermissionMap,
) {
  if (role === 'OWNER') {
    return ownerPermissionCodes;
  }
  const codes: string[] = [];
  for (const [resource, actions] of map) {
    for (const action of actions) {
      codes.push(`${resource}.${action}`);
    }
  }
  return codes.sort();
}

export async function contractPermissionsFor(userId: string, role: 'OWNER' | 'TECH') {
  const map = await canonicalPermissionsFor(userId, role);
  return contractPermissionCodes(role, map);
}

function actionsArray(actions: unknown) {
  return Array.isArray(actions) ? actions.map(String) : [];
}
