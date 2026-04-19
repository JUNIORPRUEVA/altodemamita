import { IsOptional, IsUUID } from 'class-validator';

import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';

export class SalesQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsUUID('4')
  sellerId?: string;

  @IsOptional()
  @IsUUID('4')
  clientId?: string;
}