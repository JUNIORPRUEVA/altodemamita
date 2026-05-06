import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';

import { ALLOW_DEVICE_WRITE_BYPASS_KEY } from '../decorators/allow-device-write-bypass.decorator';
import { AuthenticatedUser } from '../decorators/current-user.decorator';
import { DeviceAuthorizationService } from '../services/device-authorization.service';
import { isPanelActor } from '../utils/panel-access.util';

@Injectable()
export class DeviceWriteGuard implements CanActivate {
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
      headers?: Record<string, string | string[] | undefined>;
      body?: Record<string, unknown>;
      query?: Record<string, unknown>;
      user?: AuthenticatedUser;
      deviceAuthState?: unknown;
    }>();

    const method = request.method?.toUpperCase() ?? 'GET';
    if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
      return true;
    }

    const user = request.user;
    if (user == null) {
      return true;
    }

    if (user.type === 'panel' || isPanelActor(user)) {
      throw new ForbiddenException({
        message: 'DEVICE_WRITE_BLOCKED',
        detail: 'Las mutaciones no estan disponibles para clientes panel/PWA.',
      });
    }

    const deviceId = this.extractDeviceId(request);
    const deviceState = await this.deviceAuthorizationService.resolveCurrentAccess({
      userId: user.sub,
      clientType: user.type,
      deviceId,
      roles: user.roles,
      autoRegisterDesktop: true,
    });
    request.deviceAuthState = deviceState;

    if (deviceState.canWrite) {
      return true;
    }

    throw new ForbiddenException({
      message: 'DEVICE_WRITE_BLOCKED',
      detail: 'Este dispositivo no esta autorizado para escribir.',
      reason: deviceState.reason,
      device_id: deviceState.deviceId,
      is_primary: deviceState.isPrimary,
    });
  }

  private extractDeviceId(request: {
    headers?: Record<string, string | string[] | undefined>;
    body?: Record<string, unknown>;
    query?: Record<string, unknown>;
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

    const bodyDeviceId = request.body?.['device_id'];
    if (typeof bodyDeviceId === 'string' && bodyDeviceId.trim().length > 0) {
      return bodyDeviceId.trim();
    }

    const queryDeviceId = request.query?.['device_id'];
    if (typeof queryDeviceId === 'string' && queryDeviceId.trim().length > 0) {
      return queryDeviceId.trim();
    }

    return '';
  }
}