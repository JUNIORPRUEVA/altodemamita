import { Body, Controller, Delete, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { AuthService } from '../../application/services/auth.service';
import { CreateUserDto } from '../../application/dto/create-user.dto';
import { UpdateUserDto } from '../../application/dto/update-user.dto';

@Controller('users')
export class UsersController {
  constructor(private readonly authService: AuthService) {}

  @Get()
  @RequirePermissions(PERMISSIONS.usersRead)
  listUsers(@Query() query: PaginationQueryDto) {
    return this.authService.listUsers(query);
  }

  @Get(':id')
  @RequirePermissions(PERMISSIONS.usersRead)
  getUser(@Param('id') id: string) {
    return this.authService.getUserById(id);
  }

  @Post()
  @RequirePermissions(PERMISSIONS.usersWrite)
  createUser(@Body() dto: CreateUserDto) {
    console.log('DATA RECIBIDA:', dto);
    return this.authService.createUser(dto);
  }

  @Patch(':id')
  @RequirePermissions(PERMISSIONS.usersWrite)
  updateUser(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    console.log('DATA RECIBIDA:', dto);
    return this.authService.updateUser(id, dto);
  }

  @Delete(':id')
  @RequirePermissions(PERMISSIONS.usersWrite)
  removeUser(@Param('id') id: string) {
    return this.authService.removeUser(id);
  }
}