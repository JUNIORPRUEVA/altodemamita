import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { SyncDownloadDto } from '../../application/dto/sync-download.dto';
import { SyncUploadDto } from '../../application/dto/sync-upload.dto';
import { SyncService } from '../../application/services/sync.service';

@Controller('sync')
export class SyncController {
  constructor(private readonly syncService: SyncService) {}

  @Post('upload')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions(PERMISSIONS.syncManage)
  upload(
    @Body() dto: SyncUploadDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    return this.syncService.upload(dto);
  }

  @Get('jobs/:jobId')
  @RequirePermissions(PERMISSIONS.syncManage)
  getJob(
    @Param('jobId') jobId: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    return this.syncService.getJob(jobId);
  }

  @Get('download')
  @RequirePermissions(PERMISSIONS.syncManage)
  download(
    @Query() dto: SyncDownloadDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    return this.syncService.download(dto);
  }
}