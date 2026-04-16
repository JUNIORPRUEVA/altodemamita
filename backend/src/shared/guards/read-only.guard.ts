import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';

import { SystemConfigService } from 'src/modules/system/application/services/system-config.service';

@Injectable()
export class ReadOnlyGuard implements CanActivate {
  constructor(private readonly systemConfigService: SystemConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    if (context.getType<string>() !== 'http') {
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