import { Module } from '@nestjs/common';

import { ProductsController } from './infrastructure/controllers/products.controller';
import { ProductsService } from './application/services/products.service';

@Module({
  controllers: [ProductsController],
  providers: [ProductsService],
  exports: [ProductsService],
})
export class ProductsModule {}