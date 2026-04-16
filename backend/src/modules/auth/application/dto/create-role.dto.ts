import { IsEnum, IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { RoleCode } from '@prisma/client';

export class CreateRoleDto {
  @IsEnum(RoleCode)
  code!: RoleCode;

  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;
}