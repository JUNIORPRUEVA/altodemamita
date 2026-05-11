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
  Req,
} from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import {
  AuthenticatedUser,
  CurrentUser,
} from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { SyncDownloadDto } from '../../application/dto/sync-download.dto';
import { SyncRestoreDownloadDto } from '../../application/dto/sync-restore-download.dto';
import { SyncUploadDto } from '../../application/dto/sync-upload.dto';
import { SyncService } from '../../application/services/sync.service';

@Controller('sync')
export class SyncController {
  private readonly logger = new Logger(SyncController.name);

  constructor(private readonly syncService: SyncService) {}

  @Post('upload')
  @HttpCode(HttpStatus.OK)
  async upload(
    @Body() dto: SyncUploadDto,
    @CurrentUser() user: AuthenticatedUser,
    @Headers('x-device-id') headerDeviceId?: string,
    @Req() req?: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    const headerValue = (headerDeviceId ?? '').trim();
    const bodyValue = (dto.device_id ?? '').trim();
    const effectiveDeviceId = headerValue || bodyValue;
    const inputCounts = {
      users: dto.records.users?.length ?? 0,
      clients: dto.records.clients?.length ?? 0,
      products: dto.records.products?.length ?? 0,
      sellers: dto.records.sellers?.length ?? 0,
      sales: dto.records.sales?.length ?? 0,
      installments: dto.records.installments?.length ?? 0,
      payments: dto.records.payments?.length ?? 0,
    };
    this.logger.log(
      `[sync-upload] request userId=${user.sub} x-device-id=${headerValue || '<missing>'} bodyDeviceId=${bodyValue || '<missing>'} ` +
        `effectiveDeviceId=${effectiveDeviceId || '<missing>'} autorizado=yes ` +
        `counts={users:${inputCounts.users}, clients:${inputCounts.clients}, products:${inputCounts.products}, sellers:${inputCounts.sellers}, sales:${inputCounts.sales}, installments:${inputCounts.installments}, payments:${inputCounts.payments}}`,
    );

    try {
      const deviceAuthState = req?.['deviceAuthState'] as
        | { canWrite?: boolean; isPrimary?: boolean }
        | undefined;
      const isPrimary = deviceAuthState?.isPrimary === true;
      const result = await this.syncService.upload(dto, { isPrimary });
      const records =
        result['records'] && typeof result['records'] === 'object'
          ? (result['records'] as Partial<SyncUploadDto['records']>)
          : {};
      const countOf = (scope: keyof SyncUploadDto['records']): number => {
        const value = records[scope];
        return Array.isArray(value) ? value.length : 0;
      };

      this.logger.log(
        `[sync-upload] response userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} jobId=${result['jobId'] ?? '<unknown>'} status=${result['status'] ?? '<unknown>'} ` +
          `ackCounts={users:${countOf('users')}, clients:${countOf('clients')}, products:${countOf('products')}, sellers:${countOf('sellers')}, sales:${countOf('sales')}, installments:${countOf('installments')}, payments:${countOf('payments')}}`,
      );

      return result;
    } catch (error) {
      const deviceAuthState = req?.['deviceAuthState'] as
        | { canWrite?: boolean; isPrimary?: boolean }
        | undefined;
      const authorizedLabel = deviceAuthState == null
        ? 'unknown'
        : deviceAuthState.canWrite == true
        ? 'yes'
        : 'no';
      this.logger.error(
        `[sync-upload] failed userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} autorizado=${authorizedLabel} isPrimary=${deviceAuthState?.isPrimary === true ? 'yes' : 'no'} error=${error}`,
      );
      throw error;
    }
  }

  @Get('jobs/:jobId')
  getJob(
    @Param('jobId') jobId: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La sincronizacion operativa');
    return this.syncService.getJob(jobId);
  }

  @Get('download')
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

  @Post('restore/preview')
  @HttpCode(HttpStatus.OK)
  async previewManualRestore(
    @Body() dto: SyncDownloadDto,
    @CurrentUser() user: AuthenticatedUser,
    @Headers('x-device-id') headerDeviceId?: string,
    @Req() req?: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La restauracion manual de emergencia');
    const effectiveDeviceId = (headerDeviceId ?? dto.device_id ?? '').trim();
    const requestIp =
      (req?.['ip'] as string | undefined)?.trim() ||
      (req?.['ips'] as string[] | undefined)?.[0]?.trim() ||
      '<unknown>';

    this.logger.warn(
      `[sync-restore-preview] request userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} ip=${requestIp}`,
    );

    const result = await this.syncService.previewManualRestoreExport({
      adminUserId: user.sub,
      deviceId: effectiveDeviceId,
      requestIp,
    });

    this.logger.warn(
      `[sync-restore-preview] response userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} counts=${JSON.stringify(result['counts'] ?? {})}`,
    );

    return result;
  }

  @Post('restore/download')
  @HttpCode(HttpStatus.OK)
  async downloadManualRestore(
    @Body() dto: SyncRestoreDownloadDto,
    @CurrentUser() user: AuthenticatedUser,
    @Headers('x-device-id') headerDeviceId?: string,
    @Req() req?: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    assertOperationalAccess(user, 'La restauracion manual de emergencia');
    const effectiveDeviceId = (headerDeviceId ?? dto.device_id ?? '').trim();
    const requestIp =
      (req?.['ip'] as string | undefined)?.trim() ||
      (req?.['ips'] as string[] | undefined)?.[0]?.trim() ||
      '<unknown>';

    this.logger.warn(
      `[sync-restore-download] request userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} ip=${requestIp}`,
    );

    const result = await this.syncService.downloadManualRestoreExport({
      adminUserId: user.sub,
      adminPassword: dto.admin_password,
      confirmationText: dto.confirmation_text,
      deviceId: effectiveDeviceId,
      requestIp,
    });

    this.logger.warn(
      `[sync-restore-download] response userId=${user.sub} x-device-id=${effectiveDeviceId || '<missing>'} counts=${JSON.stringify(result['counts'] ?? {})}`,
    );

    return result;
  }
}