import { IsOptional, IsString } from 'class-validator';

export class CreateSellerDto {
  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  documentId?: string;

  @IsOptional()
  @IsString()
  phone?: string;
}