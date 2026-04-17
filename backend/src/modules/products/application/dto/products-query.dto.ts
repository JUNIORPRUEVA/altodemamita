import { Transform } from 'class-transformer';
import { IsBoolean, IsOptional } from 'class-validator';

import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';

function parseBoolean(value: unknown): boolean | unknown {
  if (typeof value === 'boolean') {
    return value;
  }

  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true' || normalized === '1') {
      return true;
    }
    if (normalized === 'false' || normalized === '0' || normalized === '') {
      return false;
    }
  }

  return value;
}

export class ProductsQueryDto extends PaginationQueryDto {
  @IsOptional()
  @Transform(({ value }: { value: unknown }) => parseBoolean(value))
  @IsBoolean()
  includeInactive = false;

  @IsOptional()
  @Transform(({ value }: { value: unknown }) => parseBoolean(value))
  @IsBoolean()
  includeDeleted = false;
}