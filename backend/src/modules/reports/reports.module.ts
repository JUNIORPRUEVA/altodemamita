import { Module } from '@nestjs/common';

import { ReportsController } from './infrastructure/controllers/reports.controller';
import { ReportsService } from './application/services/reports.service';

@Module({
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}