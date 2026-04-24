import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { CreateSellerDto } from '../../application/dto/create-seller.dto';
import { SellersQueryDto } from '../../application/dto/sellers-query.dto';
import { UpdateSellerDto } from '../../application/dto/update-seller.dto';
import { SellersService } from '../../application/services/sellers.service';

@Controller('sellers')
export class SellersController {
  constructor(private readonly sellersService: SellersService) {}

  @Post()
  @RequirePermissions(PERMISSIONS.sellersWrite)
  create(@Body() dto: CreateSellerDto) {
    return this.sellersService.create(dto);
  }

  @Get()
  @RequirePermissions(PERMISSIONS.sellersRead)
  findAll(@Query() query: SellersQueryDto) {
    return this.sellersService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.sellersRead)
  findOne(@Param('id') id: string) {
    return this.sellersService.findOne(id);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.sellersWrite)
  update(@Param('id') id: string, @Body() dto: UpdateSellerDto) {
    return this.sellersService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.sellersWrite)
  remove(@Param('id') id: string) {
    return this.sellersService.remove(id);
  }
}