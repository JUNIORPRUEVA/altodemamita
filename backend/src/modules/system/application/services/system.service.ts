import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma, RoleCode, SyncStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { SystemSetupDto } from '../dto/system-setup.dto';

@Injectable()
export class SystemService {
  constructor(private readonly prisma: PrismaService) {}

  async getStatus() {
    const [admin, company] = await this.prisma.$transaction([
      this.prisma.user.findFirst({
        where: {
          deletedAt: null,
          isActive: true,
          userRoles: {
            some: {
              deletedAt: null,
              role: {
                deletedAt: null,
                code: { in: [RoleCode.SUPER_ADMIN, RoleCode.ADMIN] },
              },
            },
          },
        },
        select: { id: true },
      }),
      this.prisma.companyProfile.findFirst({
        select: { id: true },
      }),
    ]);

    return {
      initialized: admin != null && company != null,
    };
  }

  async setup(dto: SystemSetupDto) {
    const status = await this.getStatus();
    if (status.initialized) {
      throw new BadRequestException('El sistema central ya fue inicializado.');
    }

    const companyName = dto.company.name.trim();
    const fullName = dto.admin.fullName.trim();
    const email = dto.admin.email.trim().toLowerCase();
    const username = this.normalizeUsername(dto.admin.username, email, fullName);
    const password = dto.admin.password.trim();

    if (!companyName) {
      throw new BadRequestException('El nombre de la empresa es obligatorio.');
    }
    if (!fullName) {
      throw new BadRequestException('El nombre del administrador es obligatorio.');
    }
    if (!email) {
      throw new BadRequestException('El correo del administrador es obligatorio.');
    }
    if (password.length < 8) {
      throw new BadRequestException('La contraseña inicial debe tener al menos 8 caracteres.');
    }

    const passwordHash = await bcrypt.hash(password, 10);

    return this.prisma.$transaction(async (tx) => {
      const [existingCompany, existingUser] = await Promise.all([
        tx.companyProfile.findFirst({ select: { id: true } }),
        tx.user.findFirst({
          where: {
            deletedAt: null,
            OR: [{ email }, { username }],
          },
          select: { id: true },
        }),
      ]);

      if (existingCompany) {
        throw new BadRequestException('La empresa ya fue configurada en la nube.');
      }
      if (existingUser) {
        throw new BadRequestException('Ya existe un usuario con ese correo o nombre de usuario.');
      }

      await this.ensurePermissions(tx);
      const role = await this.ensureSuperAdminRole(tx);

      const company = await tx.companyProfile.create({
        data: {
          name: companyName,
          phone: dto.company.phone?.trim() || null,
          address: dto.company.address?.trim() || null,
          logoBase64: dto.company.logoBase64?.trim() || null,
        },
        select: { id: true, name: true },
      });

      const user = await tx.user.create({
        data: {
          email,
          username,
          fullName,
          passwordHash,
          isActive: true,
          syncStatus: SyncStatus.synced,
        },
        select: { id: true, email: true, username: true },
      });

      await tx.userRole.create({
        data: {
          userId: user.id,
          roleId: role.id,
          syncStatus: SyncStatus.synced,
        },
      });

      return {
        initialized: true,
        company: {
          id: company.id,
          name: company.name,
        },
        admin: user,
      };
    });
  }

  private normalizeUsername(rawUsername: string | undefined, email: string, fullName: string): string {
    const baseValue = rawUsername?.trim() || email.split('@')[0] || fullName;
    const normalized = baseValue
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, '.')
      .replace(/\.{2,}/g, '.')
      .replace(/^\.|\.$/g, '');

    return normalized || 'admin';
  }

  private async ensurePermissions(tx: Prisma.TransactionClient) {
    for (const code of Object.values(PERMISSIONS)) {
      await tx.permission.upsert({
        where: { code },
        update: { deletedAt: null, syncStatus: SyncStatus.synced, name: code },
        create: {
          code,
          name: code,
          syncStatus: SyncStatus.synced,
        },
      });
    }

    await this.ensurePanelRole(
      tx,
      RoleCode.PANEL_VIEWER,
      'Panel Viewer',
      'Lectura del panel web sin operaciones financieras',
      [
        PERMISSIONS.clientsRead,
        PERMISSIONS.productsRead,
        PERMISSIONS.sellersRead,
        PERMISSIONS.salesRead,
        PERMISSIONS.paymentsRead,
        PERMISSIONS.installmentsRead,
        PERMISSIONS.reportsRead,
      ],
    );
    await this.ensurePanelRole(
      tx,
      RoleCode.PANEL_ADMIN,
      'Panel Admin',
      'Administracion del panel web sin operaciones financieras',
      [
        PERMISSIONS.clientsRead,
        PERMISSIONS.productsRead,
        PERMISSIONS.sellersRead,
        PERMISSIONS.salesRead,
        PERMISSIONS.paymentsRead,
        PERMISSIONS.installmentsRead,
        PERMISSIONS.reportsRead,
        PERMISSIONS.usersRead,
        PERMISSIONS.usersWrite,
        PERMISSIONS.authManage,
        PERMISSIONS.systemConfig,
        PERMISSIONS.sellersWrite,
      ],
    );
  }

  private async ensureSuperAdminRole(tx: Prisma.TransactionClient) {
    const role = await tx.role.upsert({
      where: { code: RoleCode.SUPER_ADMIN },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: {
        code: RoleCode.SUPER_ADMIN,
        name: 'Super Admin',
        description: 'Acceso total al sistema',
        syncStatus: SyncStatus.synced,
      },
      select: { id: true },
    });

    const permissions = await tx.permission.findMany({
      where: { deletedAt: null },
      select: { id: true },
    });

    for (const permission of permissions) {
      await tx.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: role.id,
            permissionId: permission.id,
          },
        },
        update: { deletedAt: null, syncStatus: SyncStatus.synced },
        create: {
          roleId: role.id,
          permissionId: permission.id,
          syncStatus: SyncStatus.synced,
        },
      });
    }

    return role;
  }

  private async ensurePanelRole(
    tx: Prisma.TransactionClient,
    code: RoleCode,
    name: string,
    description: string,
    permissionCodes: string[],
  ) {
    const role = await tx.role.upsert({
      where: { code },
      update: { deletedAt: null, syncStatus: SyncStatus.synced, name, description },
      create: {
        code,
        name,
        description,
        syncStatus: SyncStatus.synced,
      },
      select: { id: true },
    });

    const permissions = await tx.permission.findMany({
      where: { code: { in: permissionCodes }, deletedAt: null },
      select: { id: true },
    });

    await tx.rolePermission.updateMany({
      where: {
        roleId: role.id,
        deletedAt: null,
        permissionId: { notIn: permissions.map((permission) => permission.id) },
      },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.synced,
      },
    });

    for (const permission of permissions) {
      await tx.rolePermission.upsert({
        where: {
          roleId_permissionId: {
            roleId: role.id,
            permissionId: permission.id,
          },
        },
        update: { deletedAt: null, syncStatus: SyncStatus.synced },
        create: {
          roleId: role.id,
          permissionId: permission.id,
          syncStatus: SyncStatus.synced,
        },
      });
    }
  }
}