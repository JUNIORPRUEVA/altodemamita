import { Global, Module } from '@nestjs/common';

import { LoanAccountingService } from './services/loan-accounting.service';

@Global()
@Module({
  providers: [LoanAccountingService],
  exports: [LoanAccountingService],
})
export class SharedModule {}