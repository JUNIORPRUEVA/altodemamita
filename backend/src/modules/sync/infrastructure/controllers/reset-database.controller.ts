import {
  Controller,
  Delete,
  Headers,
  HttpCode,
  HttpStatus,
  UnauthorizedException,
} from '@nestjs/common';

import { Public } from 'src/shared/decorators/public.decorator';
import { AllowInReadOnly } from 'src/shared/decorators/allow-in-read-only.decorator';
import { SyncService } from '../../application/services/sync.service';

const RESET_DATABASE_ADMIN_KEY = '123456';

@Controller()
export class ResetDatabaseController {
  constructor(private readonly syncService: SyncService) {}

  @Delete('reset-database')
  @Public()
  @AllowInReadOnly()
  @HttpCode(HttpStatus.OK)
  resetDatabase(@Headers('x-admin-key') adminKey?: string) {
    if (adminKey?.trim() != RESET_DATABASE_ADMIN_KEY) {
      throw new UnauthorizedException('Admin key invalida.');
    }

    return this.syncService.resetDatabase();
  }
}