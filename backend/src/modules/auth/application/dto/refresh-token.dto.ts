import { IsIn, IsOptional, IsString } from 'class-validator';

export class RefreshTokenDto {
  @IsOptional()
  @IsString()
  token?: string;

  @IsOptional()
  @IsString()
  @IsIn(['desktop', 'panel'])
  clientType?: 'desktop' | 'panel';
}
