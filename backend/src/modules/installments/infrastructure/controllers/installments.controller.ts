import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { assertOperationalAccess } from 'src/shared/utils/panel-access.util';
import { CreateInstallmentDto } from '../../application/dto/create-installment.dto';
import { ListInstallmentsDto } from '../../application/dto/list-installments.dto';
import { UpdateInstallmentDto } from '../../application/dto/update-installment.dto';
import { InstallmentsService } from '../../application/services/installments.service';

@Controller('installments')
export class InstallmentsController {
  constructor(private readonly installmentsService: InstallmentsService) {}

  @Post()
  @RequirePermissions(PERMISSIONS.installmentsWrite)
  create(
    @Body() dto: CreateInstallmentDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La gestion de cuotas');
    return this.installmentsService.create(dto);
  }

  @Get()
  @RequirePermissions(PERMISSIONS.installmentsRead)
  findAll(@Query() query: ListInstallmentsDto) {
    return this.installmentsService.findAll(query);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.installmentsRead)
  findOne(@Param('id') id: string) {
    return this.installmentsService.findOne(id);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.installmentsWrite)
  update(
    @Param('id') id: string,
    @Body() dto: UpdateInstallmentDto,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La gestion de cuotas');
    return this.installmentsService.update(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.installmentsWrite)
  remove(
    @Param('id') id: string,
    @CurrentUser() user: { type: 'desktop' | 'panel'; roles: string[] },
  ) {
    assertOperationalAccess(user, 'La gestion de cuotas');
    return this.installmentsService.remove(id);
  }
}