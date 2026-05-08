import {
  Controller,
  Delete,
  ForbiddenException,
  Headers,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';

import { AllowInReadOnly } from 'src/shared/decorators/allow-in-read-only.decorator';
import { Public } from 'src/shared/decorators/public.decorator';
import { SyncService } from '../../application/services/sync.service';

const ADMIN_KEY = process.env.RESET_ADMIN_KEY ?? '123456';

@Controller()
export class ResetDatabaseController {
  constructor(private readonly syncService: SyncService) {}

  @Delete('reset-database')
  @Public()
  @AllowInReadOnly()
  @HttpCode(HttpStatus.OK)
  resetDatabase(@Headers('x-admin-key') adminKey: string) {
    if (!adminKey || adminKey.trim() !== ADMIN_KEY.trim()) {
      throw new ForbiddenException('Clave de administrador invalida.');
    }
    return this.syncService.resetDatabase();
  }
}