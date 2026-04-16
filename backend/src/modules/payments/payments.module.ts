import { Module } from '@nestjs/common';

import { PaymentsController } from './infrastructure/controllers/payments.controller';
import { PaymentsService } from './application/services/payments.service';

@Module({
  controllers: [PaymentsController],
  providers: [PaymentsService],
  exports: [PaymentsService],
})
export class PaymentsModule {}