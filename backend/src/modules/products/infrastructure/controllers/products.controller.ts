import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { CreateProductDto } from '../../application/dto/create-product.dto';
import { ProductsQueryDto } from '../../application/dto/products-query.dto';
import { UpdateProductDto } from '../../application/dto/update-product.dto';
import { ProductsService } from '../../application/services/products.service';

@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  @Post()
  @RequirePermissions(PERMISSIONS.productsWrite)
  create(@Body() dto: CreateProductDto) {
    return this.productsService.create(dto);
  }

  @Get()
  @RequirePermissions(PERMISSIONS.productsRead)
  findAll(@Query() query: ProductsQueryDto) {
    return this.productsService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.productsRead)
  findOne(@Param('id') id: string) {
    return this.productsService.findOne(id);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.productsWrite)
  update(@Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.productsService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.productsWrite)
  remove(@Param('id') id: string) {
    return this.productsService.remove(id);
  }
}