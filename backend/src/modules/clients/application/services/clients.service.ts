import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, SaleStatus, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { CreateClientDto } from '../dto/create-client.dto';
import { UpdateClientDto } from '../dto/update-client.dto';

@Injectable()
export class ClientsService {
  private readonly logger = new Logger(ClientsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateClientDto) {
    this.logger.log(`CREATE client dto=${this.serialize(dto)}`);
    console.log('DATA RECIBIDA:', dto);

    if (dto.code) {
      await this.ensureUniqueCode(dto.code);
    }
    await this.ensureUniqueDocument(dto.documentId);

    const result = await this.prisma.client.create({
      data: {
        ...dto,
        email: dto.email?.toLowerCase(),
        syncStatus: SyncStatus.pending,
      },
    });
    console.log('DATA GUARDADA:', result);
    return result;
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
    this.logger.log(`UPDATE client id=${id} dto=${this.serialize(dto)}`);

    await this.findOne(id);

    if (dto.code) {
      await this.ensureUniqueCode(dto.code, id);
    }
    await this.ensureUniqueDocument(dto.documentId, id);

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
    const client = await this.findOne(id);

    const activeSaleCount = await this.prisma.sale.count({
      where: {
        clientId: id,
        deletedAt: null,
        status: { not: SaleStatus.cancelled },
      },
    });
    if (activeSaleCount > 0) {
      throw new BadRequestException({
        message:
          'No puedes eliminar este cliente porque tiene una venta activa relacionada. ' +
          'Primero debes ir a Ventas y anular o eliminar esa venta.',
        errorCode: 'ENTITY_HAS_ACTIVE_SALES',
      });
    }

    await this.prisma.client.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        documentId: this.deletedDocumentPlaceholder(client.documentId, id),
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
      this.logger.warn(`CLIENT DTO INVALID duplicate_code code=${code} id=${id ?? 'new'}`);
      throw new BadRequestException('Ya existe un cliente con ese código.');
    }
  }

  private async ensureUniqueDocument(documentId?: string, id?: string) {
    const normalized = documentId?.trim();
    if (!normalized) {
      return;
    }

    const existing = await this.prisma.client.findFirst({
      where: {
        deletedAt: null,
        documentId: { equals: normalized, mode: 'insensitive' },
        id: id ? { not: id } : undefined,
      },
      select: { id: true },
    });

    if (existing) {
      throw new BadRequestException(
        'Ya existe un cliente activo con esta cédula. Verifica los datos antes de continuar.',
      );
    }
  }

  private deletedDocumentPlaceholder(documentId: string | null, id: string): string | null {
    const normalized = documentId?.trim();
    if (!normalized) {
      return null;
    }
    if (normalized.startsWith('__DELETED__')) {
      return normalized;
    }
    return `__DELETED__${id}`;
  }

  private serialize(payload: unknown): string {
    try {
      return JSON.stringify(payload);
    } catch (_) {
      return String(payload);
    }
  }
}