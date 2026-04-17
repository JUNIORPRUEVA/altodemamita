import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { CreateProductDto } from '../dto/create-product.dto';
import { ProductsQueryDto } from '../dto/products-query.dto';
import { UpdateProductDto } from '../dto/update-product.dto';

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly logger = new Logger(ProductsService.name);

  async create(dto: CreateProductDto) {
    await this.ensureUniqueCode(dto.code);

    return this.prisma.product.create({
      data: {
        code: dto.code,
        name: dto.name,
        description: dto.description,
        price: dto.price,
        financingPrice: dto.financingPrice,
        stock: dto.stock ?? 0,
        isActive: dto.isActive ?? true,
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async findAll(query: ProductsQueryDto) {
    const where = this.buildWhere(query);
    const [total, items] = await this.prisma.$transaction([
      this.prisma.product.count({ where }),
      this.prisma.product.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
    ]);

    this.logger.debug(
      `Listado products page=${query.page} limit=${query.limit} ` +
        `includeInactive=${query.includeInactive} includeDeleted=${query.includeDeleted} ` +
        `search="${query.search?.trim() ?? ''}" total=${total}`,
    );

    return {
      items,
      meta: {
        total,
        page: query.page,
        limit: query.limit,
        totalPages: Math.ceil(total / query.limit),
      },
    };
  }

  async findOne(id: string) {
    const product = await this.prisma.product.findFirst({
      where: { id, deletedAt: null },
      include: {
        sales: {
          where: { deletedAt: null },
          orderBy: { createdAt: 'desc' },
        },
      },
    });

    if (!product) {
      throw new NotFoundException('Producto no encontrado.');
    }

    return product;
  }

  async update(id: string, dto: UpdateProductDto) {
    await this.findOne(id);

    if (dto.code) {
      await this.ensureUniqueCode(dto.code, id);
    }

    return this.prisma.product.update({
      where: { id },
      data: {
        ...dto,
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.product.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.pending,
      },
    });
    return { id, removed: true };
  }

  private buildWhere(query: ProductsQueryDto): Prisma.ProductWhereInput {
    const filters: Prisma.ProductWhereInput[] = [];
    const normalizedSearch = query.search?.trim();

    if (!query.includeDeleted) {
      filters.push({ deletedAt: null });
    }

    if (!query.includeInactive) {
      filters.push({ isActive: true });
    }

    if (normalizedSearch && normalizedSearch.length > 0) {
      filters.push({
        OR: [
          { code: { contains: normalizedSearch, mode: 'insensitive' } },
          { name: { contains: normalizedSearch, mode: 'insensitive' } },
          { description: { contains: normalizedSearch, mode: 'insensitive' } },
        ],
      });
    }

    if (filters.length === 0) {
      return {};
    }

    if (filters.length == 1) {
      return filters[0];
    }

    return { AND: filters };
  }

  private async ensureUniqueCode(code: string, id?: string) {
    const product = await this.prisma.product.findFirst({
      where: {
        code,
        deletedAt: null,
        id: id ? { not: id } : undefined,
      },
    });

    if (product) {
      throw new BadRequestException('Ya existe un producto con ese código.');
    }
  }
}