import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { CreateSaleDto } from '../../application/dto/create-sale.dto';
import { SalesQueryDto } from '../../application/dto/sales-query.dto';
import { UpdateSaleDto } from '../../application/dto/update-sale.dto';
import { SalesService } from '../../application/services/sales.service';

@Controller('sales')
export class SalesController {
  constructor(private readonly salesService: SalesService) {}

  @Post()
  @RequirePermissions(PERMISSIONS.salesWrite)
  create(
    @Body() dto: CreateSaleDto,
    @CurrentUser() user: { sub: string; type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La creacion de ventas');
    return this.salesService.create(dto, user.sub);
  }

  @Get()
  @RequirePermissions(PERMISSIONS.salesRead)
  findAll(@Query() query: SalesQueryDto) {
    return this.salesService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.salesRead)
  findOne(@Param('id') id: string) {
    return this.salesService.findOne(id);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.salesWrite)
  update(
    @Param('id') id: string,
    @Body() dto: UpdateSaleDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La actualizacion de ventas');
    return this.salesService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.salesWrite)
  remove(
    @Param('id') id: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La eliminacion de ventas');
    return this.salesService.remove(id);
  }
}