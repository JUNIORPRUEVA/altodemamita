import { createHash, timingSafeEqual } from 'node:crypto';
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Prisma, RoleCode, SyncStatus } from '@prisma/client';
import * as bcrypt from 'bcrypt';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { AuthenticatedUser } from 'src/shared/decorators/current-user.decorator';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { UserPresenceService } from 'src/shared/services/user-presence.service';
import { AssignRolePermissionsDto } from '../dto/assign-role-permissions.dto';
import { AssignUserRolesDto } from '../dto/assign-user-roles.dto';
import { CreatePermissionDto } from '../dto/create-permission.dto';
import { CreateRoleDto } from '../dto/create-role.dto';
import { CreateUserDto } from '../dto/create-user.dto';
import { LoginDto } from '../dto/login.dto';
import { UpdateUserDto } from '../dto/update-user.dto';

const salesAgentPermissions = [
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
  'reports.read',
];

const REFRESH_GRACE_SECONDS = 30 * 24 * 60 * 60; // 30 days

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly userPresenceService: UserPresenceService,
  ) {}

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findFirst({
      where: {
        deletedAt: null,
        isActive: true,
        OR: [
          { email: dto.identifier.toLowerCase() },
          { username: dto.identifier.toLowerCase() },
        ],
      },
      include: {
        userRoles: {
          where: { deletedAt: null },
          include: {
            role: {
              include: {
                rolePermissions: {
                  where: { deletedAt: null },
                  include: { permission: true },
                },
              },
            },
          },
        },
      },
    });

    if (!user || !(await this.verifyPassword(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Credenciales inválidas.');
    }

    const payload = this.buildJwtPayload(user, dto.clientType ?? 'desktop');
    const accessToken = await this.jwtService.signAsync(payload);

    return {
      accessToken,
      user: payload,
    };
  }

  async refreshToken(params: {
    token?: string;
    clientType?: 'desktop' | 'panel' | 'pwa';
    authorization?: string;
  }) {
    const tokenFromHeader = (params.authorization ?? '').startsWith('Bearer ')
      ? (params.authorization ?? '').slice('Bearer '.length).trim()
      : '';
    const rawToken = (params.token ?? '').trim() || tokenFromHeader;

    if (!rawToken) {
      throw new UnauthorizedException('Token requerido para refrescar la sesión.');
    }

    let decoded: Record<string, unknown>;
    try {
      decoded = (await this.jwtService.verifyAsync(rawToken, {
        ignoreExpiration: true,
      })) as Record<string, unknown>;
    } catch {
      throw new UnauthorizedException('Token inválido.');
    }

    const sub = decoded['sub']?.toString() ?? '';
    if (!sub) {
      throw new UnauthorizedException('Token inválido.');
    }

    const iatRaw = decoded['iat'];
    const iatSeconds =
      typeof iatRaw === 'number'
        ? iatRaw
        : Number.isFinite(Number(iatRaw))
          ? Number(iatRaw)
          : null;

    if (iatSeconds == null) {
      throw new UnauthorizedException('Token inválido.');
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    if (nowSeconds - iatSeconds > REFRESH_GRACE_SECONDS) {
      throw new UnauthorizedException(
        'La sesión expiró. Inicia sesión nuevamente para continuar.',
      );
    }

    const tokenClientType = decoded['type']?.toString();
    const clientType =
      params.clientType ??
      (tokenClientType === 'panel' || tokenClientType === 'pwa'
        ? tokenClientType
        : 'desktop');

    const user = await this.findUserEntity(sub);
    if (!user || user.deletedAt != null || user.isActive !== true) {
      throw new UnauthorizedException('El usuario ya no está activo.');
    }

    const payload = this.buildJwtPayload(user, clientType);
    const accessToken = await this.jwtService.signAsync(payload);

    return {
      accessToken,
      user: payload,
    };
  }

  async me(userId: string, clientType: AuthenticatedUser['type']) {
    const user = await this.findUserEntity(userId);
    return this.buildJwtPayload(user, clientType);
  }

  async listUsers(query: PaginationQueryDto) {
    const where = this.buildUserWhere(query.search);
    const [total, items] = await this.prisma.$transaction([
      this.prisma.user.count({ where }),
      this.prisma.user.findMany({
        where,
        include: {
          userRoles: {
            where: { deletedAt: null },
            include: {
              role: {
                include: {
                  rolePermissions: {
                    where: { deletedAt: null },
                    include: { permission: true },
                  },
                },
              },
            },
          },
        },
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
    ]);

    return {
      items: items.map((user) => this.serializeUser(user)),
      meta: {
        total,
        page: query.page,
        limit: query.limit,
        totalPages: Math.ceil(total / query.limit),
      },
    };
  }

  async getUserById(id: string) {
    const user = await this.findUserEntity(id);
    return this.serializeUser(user);
  }

  private async verifyPassword(password: string, storedHash: string) {
    if (storedHash.startsWith('$2')) {
      return bcrypt.compare(password, storedHash);
    }

    if (storedHash.startsWith('v2$')) {
      const parts = storedHash.split('$');
      if (parts.length !== 4) {
        return false;
      }

      const iterations = Number(parts[1]);
      if (!Number.isFinite(iterations) || iterations <= 0) {
        return false;
      }

      const expected = this.buildLocalPasswordHash(password, parts[2], iterations);
      return this.safeEquals(expected, storedHash);
    }

    const separatorIndex = storedHash.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= storedHash.length - 1) {
      return false;
    }

    const salt = storedHash.slice(0, separatorIndex);
    const digest = createHash('sha256').update(`${salt}::${password}`).digest('hex');
    return this.safeEquals(`${salt}:${digest}`, storedHash);
  }

  private buildLocalPasswordHash(password: string, salt: string, iterations: number) {
    let bytes = Buffer.from(`${salt}::${password}`, 'utf8');
    const passwordBytes = Buffer.from(password, 'utf8');
    const saltBytes = Buffer.from(salt, 'utf8');

    for (let round = 0; round < iterations; round += 1) {
      bytes = createHash('sha256').update(Buffer.concat([
        bytes,
        passwordBytes,
        saltBytes,
        Buffer.from([
          round & 0xff,
          (round >> 8) & 0xff,
          (round >> 16) & 0xff,
          (round >> 24) & 0xff,
        ]),
      ])).digest();
    }

    return `v2$${iterations}$${salt}$${bytes.toString('hex')}`;
  }

  private safeEquals(left: string, right: string) {
    const leftBuffer = Buffer.from(left);
    const rightBuffer = Buffer.from(right);
    if (leftBuffer.length !== rightBuffer.length) {
      return false;
    }
    return timingSafeEqual(leftBuffer, rightBuffer);
  }

  async createUser(dto: CreateUserDto) {
    console.log('DATA RECIBIDA:', dto);
    await this.ensureUniqueUser(dto.email, dto.username);
    const resolvedRoleIds = await this.resolveRoleIdsForMutation(dto);

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = await this.prisma.user.create({
      data: {
        email: dto.email.toLowerCase(),
        username: dto.username.toLowerCase(),
        fullName: dto.fullName,
        passwordHash,
        isActive: dto.isActive ?? true,
        syncStatus: SyncStatus.pending,
      },
    });

    if (resolvedRoleIds.length > 0) {
      await this.assignRoles(user.id, { roleIds: resolvedRoleIds });
    }

    const result = await this.getUserById(user.id);
    console.log('DATA GUARDADA:', result);
    return result;
  }

  async updateUser(id: string, dto: UpdateUserDto) {
    console.log('DATA RECIBIDA:', dto);
    await this.findUserEntity(id);

    if (dto.email || dto.username) {
      await this.ensureUniqueUser(dto.email, dto.username, id);
    }

    const data: Prisma.UserUpdateInput = {
      syncStatus: SyncStatus.pending,
    };

    if (dto.email) {
      data.email = dto.email.toLowerCase();
    }
    if (dto.username) {
      data.username = dto.username.toLowerCase();
    }
    if (dto.fullName) {
      data.fullName = dto.fullName;
    }
    if (typeof dto.isActive === 'boolean') {
      data.isActive = dto.isActive;
    }
    if (dto.password) {
      data.passwordHash = await bcrypt.hash(dto.password, 10);
    }

    await this.prisma.user.update({ where: { id }, data });

    const resolvedRoleIds = await this.resolveRoleIdsForMutation(dto);
    if (resolvedRoleIds.length > 0) {
      await this.assignRoles(id, { roleIds: resolvedRoleIds });
    }

    const result = await this.getUserById(id);
    console.log('DATA GUARDADA:', result);
    return result;
  }

  async removeUser(id: string) {
    const user = await this.findUserEntity(id);
    await this.prisma.user.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        isActive: false,
        syncStatus: SyncStatus.pending,
      },
    });
    return { id: user.id, removed: true };
  }

  async listRoles() {
    return this.prisma.role.findMany({
      where: { deletedAt: null },
      include: {
        rolePermissions: {
          where: { deletedAt: null },
          include: { permission: true },
        },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  async createRole(dto: CreateRoleDto) {
    const existing = await this.prisma.role.findFirst({
      where: {
        deletedAt: null,
        OR: [{ code: dto.code }, { name: dto.name }],
      },
    });
    if (existing) {
      throw new BadRequestException('El rol ya existe.');
    }

    return this.prisma.role.create({
      data: {
        ...dto,
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async listPermissions() {
    return this.prisma.permission.findMany({
      where: { deletedAt: null },
      orderBy: { code: 'asc' },
    });
  }

  async createPermission(dto: CreatePermissionDto) {
    const existing = await this.prisma.permission.findFirst({
      where: { code: dto.code, deletedAt: null },
    });
    if (existing) {
      throw new BadRequestException('El permiso ya existe.');
    }

    return this.prisma.permission.create({
      data: {
        ...dto,
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async assignRoles(userId: string, dto: AssignUserRolesDto) {
    await this.findUserEntity(userId);

    const roles = await this.prisma.role.findMany({
      where: { id: { in: dto.roleIds }, deletedAt: null },
    });
    if (roles.length !== dto.roleIds.length) {
      throw new BadRequestException('Uno o más roles no existen.');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.userRole.updateMany({
        where: {
          userId,
          deletedAt: null,
          roleId: { notIn: dto.roleIds },
        },
        data: {
          deletedAt: new Date(),
          syncStatus: SyncStatus.pending,
        },
      });

      for (const roleId of dto.roleIds) {
        await tx.userRole.upsert({
          where: {
            userId_roleId: {
              userId,
              roleId,
            },
          },
          create: {
            userId,
            roleId,
            syncStatus: SyncStatus.pending,
          },
          update: {
            deletedAt: null,
            syncStatus: SyncStatus.pending,
          },
        });
      }
    });

    return this.getUserById(userId);
  }

  async assignPermissions(roleId: string, dto: AssignRolePermissionsDto) {
    const role = await this.prisma.role.findFirst({ where: { id: roleId, deletedAt: null } });
    if (!role) {
      throw new NotFoundException('Rol no encontrado.');
    }

    const permissions = await this.prisma.permission.findMany({
      where: { id: { in: dto.permissionIds }, deletedAt: null },
    });
    if (permissions.length !== dto.permissionIds.length) {
      throw new BadRequestException('Uno o más permisos no existen.');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.rolePermission.updateMany({
        where: {
          roleId,
          deletedAt: null,
          permissionId: { notIn: dto.permissionIds },
        },
        data: {
          deletedAt: new Date(),
          syncStatus: SyncStatus.pending,
        },
      });

      for (const permissionId of dto.permissionIds) {
        await tx.rolePermission.upsert({
          where: {
            roleId_permissionId: {
              roleId,
              permissionId,
            },
          },
          create: {
            roleId,
            permissionId,
            syncStatus: SyncStatus.pending,
          },
          update: {
            deletedAt: null,
            syncStatus: SyncStatus.pending,
          },
        });
      }
    });

    return this.prisma.role.findUnique({
      where: { id: roleId },
      include: {
        rolePermissions: {
          where: { deletedAt: null },
          include: { permission: true },
        },
      },
    });
  }

  private async ensureUniqueUser(email?: string, username?: string, userId?: string) {
    if (!email && !username) {
      return;
    }

    const existing = await this.prisma.user.findFirst({
      where: {
        deletedAt: null,
        id: userId ? { not: userId } : undefined,
        OR: [
          ...(email ? [{ email: email.toLowerCase() }] : []),
          ...(username ? [{ username: username.toLowerCase() }] : []),
        ],
      },
    });

    if (existing) {
      throw new BadRequestException('Ya existe un usuario con ese correo o nombre de usuario.');
    }
  }

  private buildJwtPayload(user: {
    id: string;
    email: string;
    username: string;
    fullName: string;
    isActive?: boolean;
    userRoles: Array<{
      role: {
        code: RoleCode;
        rolePermissions: Array<{ permission: { code: string } }>;
      };
    }>;
  }, clientType: AuthenticatedUser['type']) {
    const roles = user.userRoles.map((item) => item.role.code);
    const permissions = Array.from(
      new Set(
        user.userRoles.flatMap((item) =>
          item.role.rolePermissions.map((permission) => permission.permission.code),
        ),
      ),
    );

    return {
      sub: user.id,
      email: user.email,
      username: user.username,
      fullName: user.fullName,
      isActive: user.isActive ?? true,
      type: clientType,
      roles,
      permissions,
    };
  }

  private async findUserEntity(id: string) {
    const user = await this.prisma.user.findFirst({
      where: { id, deletedAt: null },
      include: {
        userRoles: {
          where: { deletedAt: null },
          include: {
            role: {
              include: {
                rolePermissions: {
                  where: { deletedAt: null },
                  include: { permission: true },
                },
              },
            },
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundException('Usuario no encontrado.');
    }

    return user;
  }

  private serializeUser(user: {
    id: string;
    email: string;
    username: string;
    fullName: string;
    isActive: boolean;
    createdAt?: Date;
    updatedAt?: Date;
    deletedAt?: Date | null;
    syncId?: string;
    syncStatus?: SyncStatus;
    userRoles: Array<{
      role: {
        id: string;
        code: RoleCode;
        name: string;
        description: string | null;
        rolePermissions?: Array<{ permission: { code: string } }>;
      };
    }>;
  }) {
    const presence = this.userPresenceService.getPresenceForUser(user.id);
    const roles = user.userRoles.map((item) => item.role);
    const permissions = Array.from(
      new Set(
        user.userRoles.flatMap((item) =>
          item.role.rolePermissions?.map((permission) => permission.permission.code) ?? [],
        ),
      ),
    );

    return {
      ...user,
      roles,
      roleCodes: roles.map((role) => role.code),
      permissions,
      passwordHash: undefined,
      userRoles: undefined,
      presence,
    };
  }

  private async resolveRoleIdsForMutation(
    dto: Pick<CreateUserDto, 'roleIds' | 'roleCode'>,
  ): Promise<string[]> {
    if (dto.roleIds?.length) {
      return dto.roleIds;
    }
    if (!dto.roleCode) {
      return [];
    }

    const role = await this.ensureOperationalRole(dto.roleCode);
    return [role.id];
  }

  private async ensureOperationalRole(roleCode: RoleCode) {
    const upsertedRole = await this.prisma.role.upsert({
      where: { code: roleCode },
      update: { deletedAt: null, syncStatus: SyncStatus.synced },
      create: {
        code: roleCode,
        name: this.resolveRoleName(roleCode),
        description: this.resolveRoleDescription(roleCode),
        syncStatus: SyncStatus.synced,
      },
    });

    const permissionCodes = roleCode == RoleCode.ADMIN || roleCode == RoleCode.SUPER_ADMIN
      ? [
          'auth.manage',
          'system.config',
          'users.read',
          'users.write',
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
          'reports.read',
          'sync.manage',
        ]
      : salesAgentPermissions;

    await this.syncRolePermissions(upsertedRole.id, permissionCodes);
    return upsertedRole;
  }

  private async syncRolePermissions(roleId: string, permissionCodes: string[]) {
    const permissions = await this.prisma.permission.findMany({
      where: { code: { in: permissionCodes }, deletedAt: null },
    });

    await this.prisma.$transaction(async (tx) => {
      await tx.rolePermission.updateMany({
        where: {
          roleId,
          deletedAt: null,
          permissionId: {
            notIn: permissions.map((permission) => permission.id),
          },
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
              roleId,
              permissionId: permission.id,
            },
          },
          create: {
            roleId,
            permissionId: permission.id,
            syncStatus: SyncStatus.synced,
          },
          update: {
            deletedAt: null,
            syncStatus: SyncStatus.synced,
          },
        });
      }
    });
  }

  private resolveRoleName(roleCode: RoleCode): string {
    switch (roleCode) {
      case RoleCode.ADMIN:
        return 'Administrador Operativo';
      case RoleCode.SALES_AGENT:
        return 'Agente de Ventas';
      case RoleCode.SUPER_ADMIN:
        return 'Super Admin';
      case RoleCode.MANAGER:
        return 'Gerente';
      case RoleCode.CASHIER:
        return 'Caja';
      case RoleCode.PANEL_ADMIN:
        return 'Panel Admin';
      case RoleCode.PANEL_VIEWER:
        return 'Panel Viewer';
    }
  }

  private resolveRoleDescription(roleCode: RoleCode): string {
    switch (roleCode) {
      case RoleCode.ADMIN:
        return 'Acceso operativo completo para el desktop.';
      case RoleCode.SALES_AGENT:
        return 'Operador comercial con acceso a clientes, ventas y cobros.';
      case RoleCode.SUPER_ADMIN:
        return 'Acceso total al sistema.';
      case RoleCode.MANAGER:
        return 'Rol gerencial operativo.';
      case RoleCode.CASHIER:
        return 'Rol operativo de caja.';
      case RoleCode.PANEL_ADMIN:
        return 'Administracion del panel web sin operaciones financieras.';
      case RoleCode.PANEL_VIEWER:
        return 'Lectura del panel web sin operaciones financieras.';
    }
  }

  private buildUserWhere(search?: string): Prisma.UserWhereInput {
    if (!search?.trim()) {
      return { deletedAt: null };
    }

    return {
      deletedAt: null,
      OR: [
        { email: { contains: search, mode: 'insensitive' } },
        { username: { contains: search, mode: 'insensitive' } },
        { fullName: { contains: search, mode: 'insensitive' } },
      ],
    };
  }
}