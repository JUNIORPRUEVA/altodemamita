import { Module } from '@nestjs/common';

import { DevicesController } from './infrastructure/controllers/devices.controller';

@Module({
  controllers: [DevicesController],
})
export class DevicesModule {}