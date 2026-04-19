import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { CreatePaymentDto } from '../../application/dto/create-payment.dto';
import { ListPaymentsDto } from '../../application/dto/list-payments.dto';
import { UpdatePaymentDto } from '../../application/dto/update-payment.dto';
import { PaymentsService } from '../../application/services/payments.service';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post()
  @RequirePermissions(PERMISSIONS.paymentsWrite)
  create(
    @Body() dto: CreatePaymentDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'El registro de pagos');
    return this.paymentsService.create(dto);
  }

  @Get()
  @RequirePermissions(PERMISSIONS.paymentsRead)
  findAll(@Query() query: ListPaymentsDto) {
    return this.paymentsService.findAll(query);
  }

  @Get('sales')
  @RequirePermissions(PERMISSIONS.paymentsRead)
  findSalesReadModel(@Query() query: PaginationQueryDto) {
    return this.paymentsService.findSalesReadModel(query);
  }

  @Get('sales/:id')
  @RequirePermissions(PERMISSIONS.paymentsRead)
  findSaleReadModel(@Param('id') id: string) {
    return this.paymentsService.findSaleReadModel(id);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.paymentsRead)
  findOne(@Param('id') id: string) {
    return this.paymentsService.findOne(id);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.paymentsWrite)
  update(
    @Param('id') id: string,
    @Body() dto: UpdatePaymentDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La actualizacion de pagos');
    return this.paymentsService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.paymentsWrite)
  remove(
    @Param('id') id: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La eliminacion de pagos');
    return this.paymentsService.remove(id);
  }
}