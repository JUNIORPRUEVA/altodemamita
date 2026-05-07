import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  Logger,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';

import { ALLOW_DEVICE_WRITE_BYPASS_KEY } from '../decorators/allow-device-write-bypass.decorator';
import { AuthenticatedUser } from '../decorators/current-user.decorator';
import { DeviceAuthorizationService } from '../services/device-authorization.service';
import { isPanelActor } from '../utils/panel-access.util';

@Injectable()
export class DeviceWriteGuard implements CanActivate {
  private readonly logger = new Logger(DeviceWriteGuard.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly deviceAuthorizationService: DeviceAuthorizationService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType<string>() !== 'http') {
      return true;
    }

    const allowBypass = this.reflector.getAllAndOverride<boolean>(
      ALLOW_DEVICE_WRITE_BYPASS_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (allowBypass) {
      return true;
    }

    const request = context.switchToHttp().getRequest<{
      method?: string;
      url?: string;
      originalUrl?: string;
      headers?: Record<string, string | string[] | undefined>;
      body?: Record<string, unknown>;
      query?: Record<string, unknown>;
      user?: AuthenticatedUser;
      deviceAuthState?: unknown;
    }>();

    const method = request.method?.toUpperCase() ?? 'GET';
    const enforceSyncDownload =
      method === 'GET' && this.isSyncDownloadRequest(request);
    if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method) && !enforceSyncDownload) {
      return true;
    }

    const user = request.user;
    if (user == null) {
      return true;
    }

    if (user.type === 'panel' || isPanelActor(user)) {
      throw new ForbiddenException({
        message: 'DEVICE_NOT_AUTHORIZED',
        detail: 'Las mutaciones no estan disponibles para clientes panel/PWA.',
      });
    }

    const headerDeviceId = this.extractHeaderDeviceId(request);
    if (!headerDeviceId) {
      this.logger.warn(
        `Blocked request without x-device-id: user=${user.sub}, method=${method}, path=${request.originalUrl ?? request.url ?? ''}`,
      );
      throw new ForbiddenException({
        message: 'DEVICE_NOT_AUTHORIZED',
        detail: 'Esta PC no esta autorizada (falta header x-device-id).',
        reason: 'missing_device_id',
      });
    }

    const payloadDeviceId = this.extractPayloadDeviceId(request);
    if (payloadDeviceId.length > 0 && payloadDeviceId !== headerDeviceId) {
      this.logger.warn(
        `Blocked request due device id mismatch: user=${user.sub}, header=${headerDeviceId}, payload=${payloadDeviceId}, method=${method}, path=${request.originalUrl ?? request.url ?? ''}`,
      );
      throw new ForbiddenException({
        message: 'DEVICE_NOT_AUTHORIZED',
        detail: 'Esta PC no esta autorizada (x-device-id no coincide con el payload).',
        reason: 'device_id_mismatch',
        header_device_id: headerDeviceId,
        payload_device_id: payloadDeviceId,
      });
    }

    const deviceState = await this.deviceAuthorizationService.resolveCurrentAccess({
      userId: user.sub,
      clientType: user.type,
      deviceId: headerDeviceId,
      roles: user.roles,
      autoRegisterDesktop: false,
    });
    request.deviceAuthState = deviceState;

    if (deviceState.canWrite) {
      return true;
    }

    this.logger.warn(
      `Blocked request: user=${user.sub}, method=${method}, path=${request.originalUrl ?? request.url ?? ''}, reason=${deviceState.reason}, deviceId=${deviceState.deviceId}`,
    );

    throw new ForbiddenException({
      message: 'DEVICE_NOT_AUTHORIZED',
      detail: 'Este dispositivo no esta autorizado para escribir.',
      reason: deviceState.reason,
      device_id: deviceState.deviceId,
      is_primary: deviceState.isPrimary,
    });
  }

  private extractHeaderDeviceId(request: {
    headers?: Record<string, string | string[] | undefined>;
  }): string {
    const header = request.headers?.['x-device-id'];
    if (typeof header === 'string' && header.trim().length > 0) {
      return header.trim();
    }
    if (Array.isArray(header) && header.length > 0) {
      for (const value of header) {
        if (value.trim().length > 0) {
          return value.trim();
        }
      }
    }
    return '';
  }

  private extractPayloadDeviceId(request: {
    body?: Record<string, unknown>;
    query?: Record<string, unknown>;
  }): string {
    const bodyDeviceId = request.body?.['device_id'];
    if (typeof bodyDeviceId === 'string' && bodyDeviceId.trim().length > 0) {
      return bodyDeviceId.trim();
    }
    const bodyDeviceIdCamel = request.body?.['deviceId'];
    if (typeof bodyDeviceIdCamel === 'string' && bodyDeviceIdCamel.trim().length > 0) {
      return bodyDeviceIdCamel.trim();
    }

    const queryDeviceId = request.query?.['device_id'];
    if (typeof queryDeviceId === 'string' && queryDeviceId.trim().length > 0) {
      return queryDeviceId.trim();
    }
    const queryDeviceIdCamel = request.query?.['deviceId'];
    if (typeof queryDeviceIdCamel === 'string' && queryDeviceIdCamel.trim().length > 0) {
      return queryDeviceIdCamel.trim();
    }

    return '';
  }

  private isSyncDownloadRequest(request: { url?: string; originalUrl?: string }): boolean {
    const path = (request.originalUrl ?? request.url ?? '').toLowerCase();
    return path.includes('/sync/download');
  }
}