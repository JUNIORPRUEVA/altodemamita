import { PrismaClient, RoleCode, SyncStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

const permissions = [
  'auth.manage',
  'system.config',
  'users.read',
  'users.write',
  'clients.read',
  'clients.write',
  'products.read',
  'products.write',
  'sales.read',
  'sales.write',
  'payments.read',
  'payments.write',
  'installments.read',
  'installments.write',
  'reports.read',
  'sync.manage',
];

const panelViewerPermissions = [
  'clients.read',
  'products.read',
  'sales.read',
  'payments.read',
  'installments.read',
  'reports.read',
];

const panelAdminPermissions = [
  ...panelViewerPermissions,
  'users.read',
  'users.write',
  'auth.manage',
  'system.config',
];

async function main(): Promise<void> {
  for (const code of permissions) {
    await prisma.permission.upsert({
      where: { code },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: {
        code,
        name: code,
        syncStatus: SyncStatus.synced,
      },
    });
  }

  const superAdminRole = await prisma.role.upsert({
    where: { code: RoleCode.SUPER_ADMIN },
    update: { deletedAt: null, syncStatus: SyncStatus.synced },
    create: {
      code: RoleCode.SUPER_ADMIN,
      name: 'Super Admin',
      description: 'Acceso total al sistema',
      syncStatus: SyncStatus.synced,
    },
  });

  const panelAdminRole = await prisma.role.upsert({
    where: { code: RoleCode.PANEL_ADMIN },
    update: { deletedAt: null, syncStatus: SyncStatus.synced },
    create: {
      code: RoleCode.PANEL_ADMIN,
      name: 'Panel Admin',
      description: 'Administracion del panel web sin operaciones financieras',
      syncStatus: SyncStatus.synced,
    },
  });

  const panelViewerRole = await prisma.role.upsert({
    where: { code: RoleCode.PANEL_VIEWER },
    update: { deletedAt: null, syncStatus: SyncStatus.synced },
    create: {
      code: RoleCode.PANEL_VIEWER,
      name: 'Panel Viewer',
      description: 'Lectura del panel web sin operaciones financieras',
      syncStatus: SyncStatus.synced,
    },
  });

  const allPermissions = await prisma.permission.findMany({
    where: { deletedAt: null },
  });

  for (const permission of allPermissions) {
    await prisma.rolePermission.upsert({
      where: {
        roleId_permissionId: {
          roleId: superAdminRole.id,
          permissionId: permission.id,
        },
      },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: {
        roleId: superAdminRole.id,
        permissionId: permission.id,
        syncStatus: SyncStatus.synced,
      },
    });
  }

  const permissionByCode = new Map(allPermissions.map((permission) => [permission.code, permission]));
  await syncRolePermissions(panelAdminRole.id, panelAdminPermissions, permissionByCode);
  await syncRolePermissions(panelViewerRole.id, panelViewerPermissions, permissionByCode);
}

async function syncRolePermissions(
  roleId: string,
  allowedCodes: string[],
  permissionByCode: Map<string, { id: string }>,
): Promise<void> {
  const allowedPermissionIds = allowedCodes
      .map((code) => permissionByCode.get(code)?.id)
      .filter((id): id is string => typeof id === 'string');

  await prisma.rolePermission.updateMany({
    where: {
      roleId,
      deletedAt: null,
      permissionId: { notIn: allowedPermissionIds },
    },
    data: {
      deletedAt: new Date(),
      syncStatus: SyncStatus.synced,
    },
  });

  for (const permissionId of allowedPermissionIds) {
    await prisma.rolePermission.upsert({
      where: {
        roleId_permissionId: {
          roleId,
          permissionId,
        },
      },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: {
        roleId,
        permissionId,
        syncStatus: SyncStatus.synced,
      },
    });
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });