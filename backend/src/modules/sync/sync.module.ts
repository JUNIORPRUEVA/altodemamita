import { Module } from '@nestjs/common';

import { SyncController } from './infrastructure/controllers/sync.controller';
import { SyncService } from './application/services/sync.service';

@Module({
  controllers: [SyncController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}