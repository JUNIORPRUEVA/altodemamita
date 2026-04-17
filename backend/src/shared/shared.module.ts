import { Global, Module } from '@nestjs/common';

import { LoanAccountingService } from './services/loan-accounting.service';
import { UserPresenceService } from './services/user-presence.service';

@Global()
@Module({
  providers: [LoanAccountingService, UserPresenceService],
  exports: [LoanAccountingService, UserPresenceService],
})
export class SharedModule {}