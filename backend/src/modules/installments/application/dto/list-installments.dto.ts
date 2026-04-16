import { Transform } from 'class-transformer';
import { IsOptional, IsString, IsUUID } from 'class-validator';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';

export class ListInstallmentsDto extends PaginationQueryDto {
  @IsOptional()
  @IsUUID('4')
  saleId?: string;

  @IsOptional()
  @Transform(({ value }: { value: unknown }) => value?.toString())
  @IsString()
  status?: string;
}