import { Transform } from 'class-transformer';
import { IsDateString, IsEnum, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import { SaleStatus } from '@prisma/client';

export class CreateSaleDto {
  @IsUUID('4')
  clientId!: string;

  @IsUUID('4')
  productId!: string;

  @IsOptional()
  @IsUUID('4')
  userId?: string;

  @IsOptional()
  @IsString()
  contractNumber?: string;

  @IsDateString()
  saleDate!: string;

  @IsOptional()
  @Transform(({ value }: { value: unknown }) =>
    value === undefined ? undefined : Number(value),
  )
  @Min(0)
  principalAmount?: number;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  downPayment!: number;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  interestRate!: number;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  termMonths!: number;

  @IsOptional()
  @IsEnum(SaleStatus)
  status?: SaleStatus;

  @IsOptional()
  @IsString()
  notes?: string;
}