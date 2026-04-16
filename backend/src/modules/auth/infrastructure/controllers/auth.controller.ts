import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';

import { CurrentUser } from 'src/shared/decorators/current-user.decorator';
import { Public } from 'src/shared/decorators/public.decorator';
import { RequirePermissions } from 'src/shared/decorators/permissions.decorator';
import { PERMISSIONS } from 'src/shared/constants/permissions.constants';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { AuthService } from '../../application/services/auth.service';
import { AssignRolePermissionsDto } from '../../application/dto/assign-role-permissions.dto';
import { AssignUserRolesDto } from '../../application/dto/assign-user-roles.dto';
import { CreatePermissionDto } from '../../application/dto/create-permission.dto';
import { CreateRoleDto } from '../../application/dto/create-role.dto';
import { CreateUserDto } from '../../application/dto/create-user.dto';
import { LoginDto } from '../../application/dto/login.dto';
import { UpdateUserDto } from '../../application/dto/update-user.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Get('me')
  me(@CurrentUser() user: { sub: string; type: 'desktop' | 'panel' }) {
    return this.authService.me(user.sub, user.type);
  }

  @Get('users')
  @RequirePermissions(PERMISSIONS.usersRead)
  listUsers(@Query() query: PaginationQueryDto) {
    return this.authService.listUsers(query);
  }

  @Get('users/:id')
  @RequirePermissions(PERMISSIONS.usersRead)
  getUser(@Param('id') id: string) {
    return this.authService.getUserById(id);
  }

  @Post('users')
  @RequirePermissions(PERMISSIONS.usersWrite)
  createUser(@Body() dto: CreateUserDto) {
    return this.authService.createUser(dto);
  }

  @Patch('users/:id')
  @RequirePermissions(PERMISSIONS.usersWrite)
  updateUser(@Param('id') id: string, @Body() dto: UpdateUserDto) {
    return this.authService.updateUser(id, dto);
  }

  @Delete('users/:id')
  @RequirePermissions(PERMISSIONS.usersWrite)
  removeUser(@Param('id') id: string) {
    return this.authService.removeUser(id);
  }

  @Post('users/:id/roles')
  @RequirePermissions(PERMISSIONS.usersWrite)
  assignRoles(@Param('id') id: string, @Body() dto: AssignUserRolesDto) {
    return this.authService.assignRoles(id, dto);
  }

  @Get('roles')
  @RequirePermissions(PERMISSIONS.authManage)
  listRoles() {
    return this.authService.listRoles();
  }

  @Post('roles')
  @RequirePermissions(PERMISSIONS.authManage)
  createRole(@Body() dto: CreateRoleDto) {
    return this.authService.createRole(dto);
  }

  @Post('roles/:id/permissions')
  @RequirePermissions(PERMISSIONS.authManage)
  assignPermissions(
    @Param('id') id: string,
    @Body() dto: AssignRolePermissionsDto,
  ) {
    return this.authService.assignPermissions(id, dto);
  }

  @Get('permissions')
  @RequirePermissions(PERMISSIONS.authManage)
  listPermissions() {
    return this.authService.listPermissions();
  }

  @Post('permissions')
  @RequirePermissions(PERMISSIONS.authManage)
  createPermission(@Body() dto: CreatePermissionDto) {
    return this.authService.createPermission(dto);
  }
}