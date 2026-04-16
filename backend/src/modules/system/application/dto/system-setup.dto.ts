import { Type } from 'class-transformer';
import { IsEmail, IsNotEmpty, IsOptional, IsString, MinLength, ValidateNested } from 'class-validator';

class SystemSetupCompanyDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  logoBase64?: string;
}

class SystemSetupAdminDto {
  @IsString()
  @IsNotEmpty()
  fullName!: string;

  @IsEmail()
  email!: string;

  @IsOptional()
  @IsString()
  username?: string;

  @IsString()
  @MinLength(8)
  password!: string;
}

export class SystemSetupDto {
  @ValidateNested()
  @Type(() => SystemSetupCompanyDto)
  company!: SystemSetupCompanyDto;

  @ValidateNested()
  @Type(() => SystemSetupAdminDto)
  admin!: SystemSetupAdminDto;
}