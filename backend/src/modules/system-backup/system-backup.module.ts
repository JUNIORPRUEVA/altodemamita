import { Module } from '@nestjs/common';

import { SystemBackupController } from './infrastructure/controllers/system-backup.controller';
import { SystemBackupService } from './application/services/system-backup.service';

@Module({
  controllers: [SystemBackupController],
  providers: [SystemBackupService],
  exports: [SystemBackupService],
})
export class SystemBackupModule {}
