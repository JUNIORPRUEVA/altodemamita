import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';

import { SystemConfigService } from 'src/modules/system/application/services/system-config.service';
import { ALLOW_IN_READ_ONLY_KEY } from '../decorators/allow-in-read-only.decorator';

@Injectable()
export class ReadOnlyGuard implements CanActivate {
  constructor(
    private readonly systemConfigService: SystemConfigService,
    private readonly reflector: Reflector,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    if (context.getType<string>() !== 'http') {
      return true;
    }

    const allowInReadOnly = this.reflector.getAllAndOverride<boolean>(
      ALLOW_IN_READ_ONLY_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (allowInReadOnly) {
      return true;
    }

    const request = context.switchToHttp().getRequest<{ method?: string }>();
    const method = request.method?.toUpperCase() ?? 'GET';

    if (method === 'GET') {
      return true;
    }

    if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
      return true;
    }

    if (!this.systemConfigService.isReadOnly()) {
      return true;
    }

    throw new ForbiddenException({
      message: 'READ_ONLY_MODE',
      detail: 'El sistema esta en modo solo lectura',
    });
  }
}