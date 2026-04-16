import { IsOptional, IsString, IsUUID } from 'class-validator';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';

export class ListPaymentsDto extends PaginationQueryDto {
  @IsOptional()
  @IsUUID('4')
  saleId?: string;

  @IsOptional()
  @IsString()
  method?: string;
}