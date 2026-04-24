import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import type { Request } from 'express';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';

import { SystemBackupService } from '../../application/services/system-backup.service';

import { getCloudBackupsDir } from '../../system-backup.paths';

const storageDir = getCloudBackupsDir();

function sanitizeUploadFilename(originalName: string): string {
  const base = path.basename(originalName || '').trim();
  if (!base) {
    return `backup_cloud_${new Date().toISOString().slice(0, 10)}.db.zip`;
  }

  return base.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_');
}

@Controller('system/backup')
export class SystemBackupController {
  constructor(private readonly service: SystemBackupService) {}

  @Post('upload')
  @HttpCode(HttpStatus.OK)
  @RequirePermissions(PERMISSIONS.syncManage)
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (
          _req: Request,
          _file: Express.Multer.File,
          cb: (error: Error | null, destination: string) => void,
        ) => {
          fs.mkdir(storageDir, { recursive: true }, (err) => {
            cb(err ?? null, storageDir);
          });
        },
        filename: (
          _req: Request,
          file: Express.Multer.File,
          cb: (error: Error | null, filename: string) => void,
        ) => {
          const safeName = sanitizeUploadFilename(file.originalname);
          cb(null, safeName);
        },
      }),
      limits: {
        fileSize: 1024 * 1024 * 1024, // 1GB
      },
    }),
  )
  async upload(
    @UploadedFile() file: Express.Multer.File,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'El respaldo en la nube');

    await this.service.cleanupOldBackups({ keepDays: 4 });

    return {
      ok: true,
      filename: file?.filename,
      sizeBytes: file?.size,
    };
  }

  @Get('list')
  @RequirePermissions(PERMISSIONS.syncManage)
  async list(@CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] }) {
    assertOperationalAccess(user, 'El respaldo en la nube');
    return {
      items: await this.service.listBackups(),
    };
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.syncManage)
  async delete(
    @Param('id') id: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'El respaldo en la nube');
    return this.service.deleteBackup(id);
  }
}
