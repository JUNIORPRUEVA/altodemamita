import { Global, Module } from '@nestjs/common';

import { SystemConfigService } from './application/services/system-config.service';
import { SystemService } from './application/services/system.service';
import { SystemController } from './infrastructure/controllers/system.controller';

@Global()
@Module({
  controllers: [SystemController],
  providers: [SystemService, SystemConfigService],
  exports: [SystemConfigService],
})
export class SystemModule {}