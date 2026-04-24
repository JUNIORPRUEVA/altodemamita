import { Module } from '@nestjs/common';

import { ResetDatabaseController } from './infrastructure/controllers/reset-database.controller';
import { SyncController } from './infrastructure/controllers/sync.controller';
import { SyncService } from './application/services/sync.service';

@Module({
  controllers: [SyncController, ResetDatabaseController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}