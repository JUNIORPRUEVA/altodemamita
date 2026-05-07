import {
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';

import { AllowInReadOnly } from 'src/shared/decorators/allow-in-read-only.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { SyncService } from '../../application/services/sync.service';

@Controller()
export class ResetDatabaseController {
  constructor(private readonly syncService: SyncService) {}

  @Delete('reset-database')
  @AllowInReadOnly()
  @RequirePermissions(PERMISSIONS.systemConfig, PERMISSIONS.syncManage)
  @HttpCode(HttpStatus.OK)
  resetDatabase() {
    return this.syncService.resetDatabase();
  }
}