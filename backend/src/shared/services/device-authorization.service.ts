import { BadRequestException, Injectable, Logger } from '@nestjs/common';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { AuthenticatedUser } from '../decorators/current-user.decorator';
import { isPanelActor } from '../utils/panel-access.util';

export interface DeviceAccessState {
  userId: string;
  clientType: AuthenticatedUser['type'];
  deviceId: string;
  deviceName: string | null;
  platform: string | null;
  isPrimary: boolean;
  canWrite: boolean;
  revokedAt: string | null;
  lastValidatedAt: string;
  reason:
    | 'panel_read_only'
    | 'missing_device_id'
    | 'authorized'
    | 'auto_registered_primary'
    | 'registered_secondary'
    | 'device_not_registered'
    | 'device_revoked'
    | 'device_not_primary';
}

export interface AuthorizedDeviceSummary {
  deviceId: string;
  deviceName: string | null;
  platform: string | null;
  isPrimary: boolean;
  canWrite: boolean;
  revokedAt: string | null;
  lastSeenAt: string | null;
  updatedAt: string;
}

@Injectable()
export class DeviceAuthorizationService {
  private readonly logger = new Logger(DeviceAuthorizationService.name);

  constructor(private readonly prisma: PrismaService) {}

  private static readonly manualDeviceRegistrationEnabled = true;

  private normalizeClientType(clientType: AuthenticatedUser['type']): AuthenticatedUser['type'] {
    if (clientType === 'panel' || clientType === 'pwa') {
      return clientType;
    }
    return 'desktop';
  }

  async resolveCurrentAccess(options: {
    userId: string;
    clientType: AuthenticatedUser['type'];
    deviceId?: string | null;
    deviceName?: string | null;
    platform?: string | null;
    roles?: string[];
    autoRegisterDesktop?: boolean;
  }): Promise<DeviceAccessState> {
    const clientType = this.normalizeClientType(options.clientType);
    const deviceId = this.normalizeDeviceId(options.deviceId);
    const deviceName = this.normalizeOptionalText(options.deviceName);
    const platform = this.normalizeOptionalText(options.platform);
    const now = new Date();

    if (clientType === 'panel' || isPanelActor({ type: clientType, roles: options.roles ?? [] })) {
      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName,
        platform,
        isPrimary: false,
        canWrite: false,
        revokedAt: null,
        now,
        reason: 'panel_read_only',
      });
    }

    if (!deviceId) {
      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId: '',
        deviceName,
        platform,
        isPrimary: false,
        canWrite: false,
        revokedAt: null,
        now,
        reason: 'missing_device_id',
      });
    }

    const activePrimary = await this.prisma.authorizedDevice.findFirst({
      where: {
        userId: options.userId,
        revokedAt: null,
        isPrimary: true,
        canWrite: true,
      },
      orderBy: { updatedAt: 'desc' },
    });

    let device = await this.prisma.authorizedDevice.findFirst({
      where: {
        userId: options.userId,
        deviceId,
      },
    });

    const canAutoRegister =
      options.autoRegisterDesktop == true &&
      !DeviceAuthorizationService.manualDeviceRegistrationEnabled;

    if (!device && canAutoRegister) {
      device = await this.prisma.authorizedDevice.create({
        data: {
          userId: options.userId,
          companyProfileId: await this.resolveCompanyProfileId(),
          deviceId,
          deviceName,
          platform,
          isPrimary: activePrimary == null,
          canWrite: activePrimary == null,
          lastSeenAt: now,
        },
      });

      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName: device.deviceName,
        platform: device.platform,
        isPrimary: device.isPrimary,
        canWrite: device.canWrite,
        revokedAt: device.revokedAt?.toISOString() ?? null,
        now,
        reason: activePrimary == null
            ? 'auto_registered_primary'
            : 'registered_secondary',
      });
    }

    if (device == null) {
      this.logger.warn(
        `Device not registered: user=${options.userId}, deviceId=${deviceId}`,
      );
      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName,
        platform,
        isPrimary: false,
        canWrite: false,
        revokedAt: null,
        now,
        reason: 'device_not_registered',
      });
    }

    if (activePrimary == null && options.autoRegisterDesktop == true) {
      device = await this.prisma.authorizedDevice.update({
        where: { id: device.id },
        data: {
          isPrimary: true,
          canWrite: true,
          revokedAt: null,
          lastSeenAt: now,
          deviceName,
          platform,
        },
      });

      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName: device.deviceName,
        platform: device.platform,
        isPrimary: true,
        canWrite: true,
        revokedAt: null,
        now,
        reason: 'auto_registered_primary',
      });
    }

    device = await this.prisma.authorizedDevice.update({
      where: { id: device.id },
      data: {
        lastSeenAt: now,
        deviceName,
        platform,
      },
    });

    if (device.revokedAt != null) {
      this.logger.warn(
        `Device revoked: user=${options.userId}, deviceId=${deviceId}`,
      );
      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName: device.deviceName,
        platform: device.platform,
        isPrimary: false,
        canWrite: false,
        revokedAt: device.revokedAt.toISOString(),
        now,
        reason: 'device_revoked',
      });
    }

    const canWrite = device.isPrimary && device.canWrite;
    this.logger.log(
      `Device access resolved: user=${options.userId}, deviceId=${deviceId}, canWrite=${canWrite}, isPrimary=${device.isPrimary}, reason=${canWrite ? 'authorized' : 'device_not_primary'}`,
    );
    return this.buildState({
      userId: options.userId,
      clientType,
      deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      isPrimary: device.isPrimary,
      canWrite,
      revokedAt: null,
      now,
      reason: canWrite ? 'authorized' : 'device_not_primary',
    });
  }

  registerDevice(options: {
    userId: string;
    clientType: AuthenticatedUser['type'];
    deviceId?: string | null;
    deviceName?: string | null;
    platform?: string | null;
    roles?: string[];
  }): Promise<DeviceAccessState> {
    return this.resolveCurrentAccess({
      ...options,
      autoRegisterDesktop: false,
    });
  }

  async listAuthorizedDevices(userId: string): Promise<AuthorizedDeviceSummary[]> {
    const devices = await this.prisma.authorizedDevice.findMany({
      where: { userId },
      orderBy: [{ isPrimary: 'desc' }, { updatedAt: 'desc' }],
      select: {
        deviceId: true,
        deviceName: true,
        platform: true,
        isPrimary: true,
        canWrite: true,
        revokedAt: true,
        lastSeenAt: true,
        updatedAt: true,
      },
    });

    return devices.map((device) => ({
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      isPrimary: device.isPrimary,
      canWrite: device.canWrite,
      revokedAt: device.revokedAt?.toISOString() ?? null,
      lastSeenAt: device.lastSeenAt?.toISOString() ?? null,
      updatedAt: device.updatedAt.toISOString(),
    }));
  }

  async activateSingleDevice(options: {
    userId: string;
    actorType: AuthenticatedUser['type'];
    roles?: string[];
    deviceId: string;
    deviceName?: string | null;
    platform?: string | null;
  }): Promise<DeviceAccessState> {
    const normalizedDeviceId = this.normalizeDeviceId(options.deviceId);
    if (!normalizedDeviceId) {
      throw new BadRequestException('Debe especificar un device_id valido.');
    }

    const now = new Date();
    const companyProfileId = await this.resolveCompanyProfileId();
    const deviceName = this.normalizeOptionalText(options.deviceName);
    const platform = this.normalizeOptionalText(options.platform);

    await this.prisma.$transaction(async (tx) => {
      await tx.authorizedDevice.updateMany({
        where: {
          userId: options.userId,
          revokedAt: null,
          deviceId: { not: normalizedDeviceId },
        },
        data: {
          isPrimary: false,
          canWrite: false,
          revokedAt: now,
          updatedAt: now,
        },
      });

      const existing = await tx.authorizedDevice.findFirst({
        where: {
          userId: options.userId,
          deviceId: normalizedDeviceId,
        },
      });

      if (existing == null) {
        await tx.authorizedDevice.create({
          data: {
            userId: options.userId,
            companyProfileId,
            deviceId: normalizedDeviceId,
            deviceName,
            platform,
            isPrimary: true,
            canWrite: true,
            revokedAt: null,
            lastSeenAt: now,
          },
        });
        return;
      }

      await tx.authorizedDevice.update({
        where: { id: existing.id },
        data: {
          companyProfileId: existing.companyProfileId ?? companyProfileId,
          deviceName,
          platform,
          isPrimary: true,
          canWrite: true,
          revokedAt: null,
          lastSeenAt: now,
        },
      });
    });

    this.logger.log(
      `Device activated: user=${options.userId}, deviceId=${normalizedDeviceId}, actor=${options.actorType}`,
    );

    return this.buildState({
      userId: options.userId,
      clientType: 'desktop',
      deviceId: normalizedDeviceId,
      deviceName,
      platform,
      isPrimary: true,
      canWrite: true,
      revokedAt: null,
      now,
      reason: 'authorized',
    });
  }

  async claimPrimary(options: {
    userId: string;
    clientType: AuthenticatedUser['type'];
    deviceId?: string | null;
    deviceName?: string | null;
    platform?: string | null;
    roles?: string[];
  }): Promise<DeviceAccessState> {
    const clientType = this.normalizeClientType(options.clientType);
    const deviceId = this.normalizeDeviceId(options.deviceId);
    const deviceName = this.normalizeOptionalText(options.deviceName);
    const platform = this.normalizeOptionalText(options.platform);

    if (clientType !== 'desktop') {
      return this.buildState({
        userId: options.userId,
        clientType,
        deviceId,
        deviceName,
        platform,
        isPrimary: false,
        canWrite: false,
        revokedAt: null,
        now: new Date(),
        reason: 'panel_read_only',
      });
    }

    const now = new Date();
    const companyProfileId = await this.resolveCompanyProfileId();
    await this.prisma.$transaction(async (tx) => {
      await tx.authorizedDevice.updateMany({
        where: {
          userId: options.userId,
          revokedAt: null,
        },
        data: {
          isPrimary: false,
          canWrite: false,
          updatedAt: now,
        },
      });

      const existing = await tx.authorizedDevice.findFirst({
        where: {
          userId: options.userId,
          deviceId,
        },
      });

      if (existing == null) {
        await tx.authorizedDevice.create({
          data: {
            userId: options.userId,
            companyProfileId,
            deviceId,
            deviceName,
            platform,
            isPrimary: true,
            canWrite: true,
            revokedAt: null,
            lastSeenAt: now,
          },
        });
        return;
      }

      await tx.authorizedDevice.update({
        where: { id: existing.id },
        data: {
          companyProfileId: existing.companyProfileId ?? companyProfileId,
          deviceName,
          platform,
          isPrimary: true,
          canWrite: true,
          revokedAt: null,
          lastSeenAt: now,
        },
      });
    });

    return this.resolveCurrentAccess({
      userId: options.userId,
      clientType,
      deviceId,
      deviceName,
      platform,
      roles: options.roles,
      autoRegisterDesktop: false,
    });
  }

  async revokeDevice(userId: string, deviceId: string): Promise<{ revoked: boolean }> {
    const normalizedDeviceId = this.normalizeDeviceId(deviceId);
    if (!normalizedDeviceId) {
      return { revoked: false };
    }

    const result = await this.prisma.authorizedDevice.updateMany({
      where: {
        userId,
        deviceId: normalizedDeviceId,
        revokedAt: null,
      },
      data: {
        revokedAt: new Date(),
        isPrimary: false,
        canWrite: false,
      },
    });

    return { revoked: result.count > 0 };
  }

  private buildState(input: {
    userId: string;
    clientType: AuthenticatedUser['type'];
    deviceId: string;
    deviceName: string | null;
    platform: string | null;
    isPrimary: boolean;
    canWrite: boolean;
    revokedAt: string | null;
    now: Date;
    reason: DeviceAccessState['reason'];
  }): DeviceAccessState {
    return {
      userId: input.userId,
      clientType: input.clientType,
      deviceId: input.deviceId,
      deviceName: input.deviceName,
      platform: input.platform,
      isPrimary: input.isPrimary,
      canWrite: input.canWrite,
      revokedAt: input.revokedAt,
      lastValidatedAt: input.now.toISOString(),
      reason: input.reason,
    };
  }

  private normalizeDeviceId(value?: string | null): string {
    return (value ?? '').trim();
  }

  private normalizeOptionalText(value?: string | null): string | null {
    const normalized = (value ?? '').trim();
    return normalized.length === 0 ? null : normalized;
  }

  private async resolveCompanyProfileId(): Promise<string | null> {
    const company = await this.prisma.companyProfile.findFirst({
      select: { id: true },
      orderBy: { createdAt: 'asc' },
    });
    return company?.id ?? null;
  }
}