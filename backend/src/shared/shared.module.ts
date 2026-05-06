import { Global, Module } from '@nestjs/common';

import { DeviceAuthorizationService } from './services/device-authorization.service';
import { LoanAccountingService } from './services/loan-accounting.service';
import { UserPresenceService } from './services/user-presence.service';

@Global()
@Module({
  providers: [
    DeviceAuthorizationService,
    LoanAccountingService,
    UserPresenceService,
  ],
  exports: [
    DeviceAuthorizationService,
    LoanAccountingService,
    UserPresenceService,
  ],
})
export class SharedModule {}