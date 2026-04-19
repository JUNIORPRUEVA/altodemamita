import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { SellersQueryDto } from '../dto/sellers-query.dto';

@Injectable()
export class SellersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(query: SellersQueryDto) {
    const where = this.buildWhere(query.search);
    const [total, items] = await this.prisma.$transaction([
      this.prisma.seller.count({ where }),
      this.prisma.seller.findMany({
        where,
        orderBy: { name: 'asc' },
        skip: (query.page - 1) * query.limit,
        take: query.limit,
      }),
    ]);

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
    const seller = await this.prisma.seller.findFirst({
      where: { id, deletedAt: null },
      include: {
        sales: {
          where: { deletedAt: null },
          orderBy: { createdAt: 'desc' },
          include: {
            client: true,
            product: true,
          },
        },
      },
    });

    if (!seller) {
      throw new NotFoundException('Vendedor no encontrado.');
    }

    return seller;
  }

  private buildWhere(search?: string): Prisma.SellerWhereInput {
    if (!search?.trim()) {
      return { deletedAt: null };
    }

    return {
      deletedAt: null,
      OR: [
        { name: { contains: search, mode: 'insensitive' } },
        { documentId: { contains: search, mode: 'insensitive' } },
        { phone: { contains: search, mode: 'insensitive' } },
      ],
    };
  }
}