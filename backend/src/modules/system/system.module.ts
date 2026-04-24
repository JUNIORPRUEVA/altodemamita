import { Global, Module } from '@nestjs/common';

import { SystemConfigService } from './application/services/system-config.service';
import { SystemService } from './application/services/system.service';
import { HealthController } from './infrastructure/controllers/health.controller';
import { SystemController } from './infrastructure/controllers/system.controller';

@Global()
@Module({
  controllers: [SystemController, HealthController],
  providers: [SystemService, SystemConfigService],
  exports: [SystemConfigService],
})
export class SystemModule {}