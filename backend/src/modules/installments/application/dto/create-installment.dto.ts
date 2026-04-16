import { Transform } from 'class-transformer';
import { IsDateString, IsEnum, IsOptional, IsUUID, Min } from 'class-validator';
import { InstallmentStatus } from '@prisma/client';

export class CreateInstallmentDto {
  @IsUUID('4')
  saleId!: string;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(1)
  installmentNumber!: number;

  @IsDateString()
  dueDate!: string;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  amount!: number;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  principalAmount!: number;

  @Transform(({ value }: { value: unknown }) => Number(value))
  @Min(0)
  interestAmount!: number;

  @IsOptional()
  @IsEnum(InstallmentStatus)
  status?: InstallmentStatus;
}