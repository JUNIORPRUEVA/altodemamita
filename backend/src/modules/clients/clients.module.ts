import { Module } from '@nestjs/common';

import { ClientsController } from './infrastructure/controllers/clients.controller';
import { ClientsService } from './application/services/clients.service';

@Module({
  controllers: [ClientsController],
  providers: [ClientsService],
  exports: [ClientsService],
})
export class ClientsModule {}