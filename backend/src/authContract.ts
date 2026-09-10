import type { AuthUser } from './auth';
import { ownerPermissionCodes } from './rbac';

export type AuthContractUser = AuthUser & {
  sub: string;
  username: string;
  fullName: string;
  isActive: boolean;
  type: 'desktop';
  roles: string[];
  permissions: string[];
};

export function authRoleCodes(role: AuthUser['role']) {
  return role === 'OWNER' ? ['SUPER_ADMIN'] : ['SALES_AGENT'];
}

/**
 * Codigos de permiso expuestos al cliente. OWNER recibe el catalogo
 * administrativo completo; cualquier otro rol recibe exactamente los permisos
 * persistidos para su usuario (nunca una lista vacia si la base los tiene).
 */
export function authPermissionCodes(role: AuthUser['role'], explicitPermissions: string[] = []) {
  if (role === 'OWNER') return ownerPermissionCodes;
  return explicitPermissions;
}

export function usernameFromEmail(email: string) {
  const localPart = email.trim().toLowerCase().split('@')[0]?.trim() ?? '';
  return localPart || 'usuario';
}

export function buildAuthContractUser(user: AuthUser, permissions: string[] = []): AuthContractUser {
  return {
    ...user,
    sub: user.id,
    username: usernameFromEmail(user.email),
    fullName: user.name,
    isActive: true,
    type: 'desktop',
    roles: authRoleCodes(user.role),
    permissions: authPermissionCodes(user.role, permissions),
  };
}
