import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { CreateClientDto } from '../dto/create-client.dto';
import { UpdateClientDto } from '../dto/update-client.dto';

@Injectable()
export class ClientsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateClientDto) {
    if (dto.code) {
      await this.ensureUniqueCode(dto.code);
    }

    return this.prisma.client.create({
      data: {
        ...dto,
        email: dto.email?.toLowerCase(),
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async findAll(query: PaginationQueryDto) {
    const where = this.buildWhere(query.search);
    const [total, items] = await this.prisma.$transaction([
      this.prisma.client.count({ where }),
      this.prisma.client.findMany({
        where,
        orderBy: { createdAt: 'desc' },
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
    const client = await this.prisma.client.findFirst({
      where: { id, deletedAt: null },
      include: {
        sales: {
          where: { deletedAt: null },
          orderBy: { createdAt: 'desc' },
        },
      },
    });
    if (!client) {
      throw new NotFoundException('Cliente no encontrado.');
    }
    return client;
  }

  async update(id: string, dto: UpdateClientDto) {
    await this.findOne(id);

    if (dto.code) {
      await this.ensureUniqueCode(dto.code, id);
    }

    return this.prisma.client.update({
      where: { id },
      data: {
        ...dto,
        email: dto.email?.toLowerCase(),
        syncStatus: SyncStatus.pending,
      },
    });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.client.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.pending,
      },
    });
    return { id, removed: true };
  }

  private buildWhere(search?: string): Prisma.ClientWhereInput {
    const normalizedSearch = search?.trim();
    if (!normalizedSearch) {
      return { deletedAt: null };
    }

    const tokens = normalizedSearch
      .split(/\s+/)
      .map((value) => value.trim())
      .filter((value) => value.length > 0);

    const tokenFilters = tokens.map<Prisma.ClientWhereInput>((token) => {
      return {
        OR: [
          { firstName: { contains: token, mode: 'insensitive' } },
          { lastName: { contains: token, mode: 'insensitive' } },
          { documentId: { contains: token, mode: 'insensitive' } },
          { email: { contains: token, mode: 'insensitive' } },
          { phone: { contains: token, mode: 'insensitive' } },
        ],
      };
    });

    const broadFilter: Prisma.ClientWhereInput = {
      OR: [
        { firstName: { contains: normalizedSearch, mode: 'insensitive' } },
        { lastName: { contains: normalizedSearch, mode: 'insensitive' } },
        { documentId: { contains: normalizedSearch, mode: 'insensitive' } },
        { email: { contains: normalizedSearch, mode: 'insensitive' } },
        { phone: { contains: normalizedSearch, mode: 'insensitive' } },
      ],
    };

    return {
      AND: [
        { deletedAt: null },
        tokens.length > 1
          ? { OR: [broadFilter, { AND: tokenFilters }] }
          : broadFilter,
      ],
    };
  }

  private async ensureUniqueCode(code: string, id?: string) {
    const client = await this.prisma.client.findFirst({
      where: {
        code,
        deletedAt: null,
        id: id ? { not: id } : undefined,
      },
    });

    if (client) {
      throw new BadRequestException('Ya existe un cliente con ese código.');
    }
  }
}