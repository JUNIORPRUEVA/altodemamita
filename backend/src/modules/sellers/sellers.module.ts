import { Module } from '@nestjs/common';

import { SellersController } from './infrastructure/controllers/sellers.controller';
import { SellersService } from './application/services/sellers.service';

@Module({
  controllers: [SellersController],
  providers: [SellersService],
  exports: [SellersService],
})
export class SellersModule {}