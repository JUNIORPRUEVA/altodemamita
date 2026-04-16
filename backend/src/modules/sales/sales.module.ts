import { Module } from '@nestjs/common';

import { SalesController } from './infrastructure/controllers/sales.controller';
import { SalesService } from './application/services/sales.service';

@Module({
  controllers: [SalesController],
  providers: [SalesService],
  exports: [SalesService],
})
export class SalesModule {}