import { Module } from '@nestjs/common';

import { InstallmentsController } from './infrastructure/controllers/installments.controller';
import { InstallmentsService } from './application/services/installments.service';

@Module({
  controllers: [InstallmentsController],
  providers: [InstallmentsService],
  exports: [InstallmentsService],
})
export class InstallmentsModule {}