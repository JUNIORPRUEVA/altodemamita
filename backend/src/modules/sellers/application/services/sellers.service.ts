import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { CreateSellerDto } from '../dto/create-seller.dto';
import { SellersQueryDto } from '../dto/sellers-query.dto';
import { UpdateSellerDto } from '../dto/update-seller.dto';

@Injectable()
export class SellersService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateSellerDto) {
    console.log('DATA RECIBIDA:', dto);
    await this.ensureUniqueDocument(dto.documentId);
    const result = await this.prisma.seller.create({
      data: {
        name: dto.name,
        documentId: dto.documentId,
        phone: dto.phone,
        syncStatus: SyncStatus.pending,
      },
    });
    console.log('DATA GUARDADA:', result);
    return result;
  }

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

  async update(id: string, dto: UpdateSellerDto) {
    console.log('DATA RECIBIDA:', dto);
    await this.findOne(id);
    await this.ensureUniqueDocument(dto.documentId, id);
    const result = await this.prisma.seller.update({
      where: { id },
      data: {
        name: dto.name,
        documentId: dto.documentId,
        phone: dto.phone,
        syncStatus: SyncStatus.pending,
      },
    });
    console.log('DATA GUARDADA:', result);
    return result;
  }

  async remove(id: string) {
    await this.findOne(id);
    const result = await this.prisma.seller.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.pending,
      },
    });
    console.log('DATA GUARDADA:', result);
    return { id: result.id, removed: true };
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

  private async ensureUniqueDocument(documentId?: string, excludeId?: string) {
    const normalizedDocumentId = documentId?.trim();
    if (normalizedDocumentId == null || normalizedDocumentId.length === 0) {
      return;
    }

    const existing = await this.prisma.seller.findFirst({
      where: {
        deletedAt: null,
        documentId: normalizedDocumentId,
        id: excludeId ? { not: excludeId } : undefined,
      },
    });
    if (existing) {
      throw new BadRequestException('Ya existe un vendedor con esa cédula.');
    }
  }
}