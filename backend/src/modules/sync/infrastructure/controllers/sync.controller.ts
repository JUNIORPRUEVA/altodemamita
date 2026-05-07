import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Logger,
  Param,
  Post,
  Query,
} from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import {
  AuthenticatedUser,
  CurrentUser,
} from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { SyncDownloadDto } from '../../application/dto/sync-download.dto';
import { SyncUploadDto } from '../../application/dto/sync-upload.dto';
import { SyncService } from '../../application/services/sync.service';

@Controller('sync')
export class SyncController {
  private readonly logger = new Logger(SyncController.name);

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
  async download(
    @Query() dto: SyncDownloadDto,
    @CurrentUser() user: AuthenticatedUser,
    @Headers('x-device-id') headerDeviceId?: string,
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    const effectiveDeviceId = (headerDeviceId ?? dto.device_id ?? '').trim();
    this.logger.log(
      `[sync-download] request userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} autorizado=yes`,
    );

    try {
      const result = await this.syncService.download(dto);
      const records =
        result['records'] && typeof result['records'] === 'object'
          ? (result['records'] as Record<string, unknown>)
          : {};
      const countOf = (scope: string): number => {
        const value = records[scope];
        return Array.isArray(value) ? value.length : 0;
      };

      this.logger.log(
        `[sync-download] response userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} ` +
          `counts={sellers:${countOf('sellers')}, products:${countOf('products')}, clients:${countOf('clients')}, ` +
          `sales:${countOf('sales')}, payments:${countOf('payments')}, installments:${countOf('installments')}}`,
      );

      return result;
    } catch (error) {
      this.logger.error(
        `[sync-download] failed userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} autorizado=no error=${error}`,
      );
      throw error;
    }
  }
}