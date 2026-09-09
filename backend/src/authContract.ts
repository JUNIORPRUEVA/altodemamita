import type { AuthUser } from './auth';

export type AuthContractUser = AuthUser & {
  sub: string;
  username: string;
  fullName: string;
  isActive: boolean;
  type: 'desktop';
  roles: string[];
  permissions: string[];
};

const ownerPermissions = [
  'clients.read',
  'clients.write',
  'products.read',
  'products.write',
  'sellers.read',
  'sellers.write',
  'sales.read',
  'sales.write',
  'payments.read',
  'payments.write',
  'installments.read',
  'installments.write',
  'users.read',
  'users.write',
  'reports.read',
  'sync.manage',
];

export function authRoleCodes(role: AuthUser['role']) {
  return role === 'OWNER' ? ['SUPER_ADMIN'] : ['SALES_AGENT'];
}

export function authPermissionCodes(role: AuthUser['role'], explicitPermissions: string[] = []) {
  if (role === 'OWNER') return ownerPermissions;
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
