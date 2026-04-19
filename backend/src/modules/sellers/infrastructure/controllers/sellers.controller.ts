import { Controller, Get, Param, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { SellersQueryDto } from '../../application/dto/sellers-query.dto';
import { SellersService } from '../../application/services/sellers.service';

@Controller('sellers')
export class SellersController {
  constructor(private readonly sellersService: SellersService) {}

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
}