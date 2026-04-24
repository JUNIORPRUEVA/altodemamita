import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, SaleStatus, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { RealtimeEventsService } from 'src/modules/realtime/realtime-events.service';
import { LoanAccountingService } from 'src/shared/services/loan-accounting.service';
import { CreateSaleDto } from '../dto/create-sale.dto';
import { SalesQueryDto } from '../dto/sales-query.dto';
import { UpdateSaleDto } from '../dto/update-sale.dto';

@Injectable()
export class SalesService {
  private readonly logger = new Logger(SalesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
    private readonly realtimeEvents: RealtimeEventsService,
  ) {}

  async create(dto: CreateSaleDto, actorUserId: string) {
    this.logger.log(`CREATE sale actorUserId=${actorUserId} dto=${this.serialize(dto)}`);
    console.log('DATA RECIBIDA:', dto);
    const client = await this.prisma.client.findFirst({ where: { id: dto.clientId, deletedAt: null } });
    if (!client) {
      throw new BadRequestException('Cliente no encontrado.');
    }

    const product = await this.prisma.product.findFirst({ where: { id: dto.productId, deletedAt: null } });
    if (!product || !product.isActive) {
      throw new BadRequestException('Producto no disponible.');
    }
    if (product.stock <= 0) {
      throw new BadRequestException('El producto no tiene stock disponible.');
    }

    const resolvedUserId = dto.userId ?? actorUserId;
    const user = await this.prisma.user.findFirst({ where: { id: resolvedUserId, deletedAt: null, isActive: true } });
    if (!user) {
      throw new BadRequestException('Usuario responsable no válido.');
    }

    const principalAmount = dto.principalAmount ?? Number(product.financingPrice ?? product.price);
    if (principalAmount <= 0) {
      throw new BadRequestException('El monto principal debe ser mayor que cero.');
    }
    if (dto.downPayment > principalAmount) {
      throw new BadRequestException('La inicial no puede ser mayor que el monto principal.');
    }
    if (dto.termMonths < 0) {
      throw new BadRequestException('El plazo no puede ser negativo.');
    }

    const saleDate = new Date(dto.saleDate);
    const schedule = this.accountingService.calculateSchedule({
      principalAmount,
      downPayment: dto.downPayment,
      interestRate: dto.interestRate,
      termMonths: dto.termMonths,
      saleDate,
    });

    const sale = await this.prisma.$transaction(async (tx) => {
      const createdSale = await tx.sale.create({
        data: {
          clientId: dto.clientId,
          productId: dto.productId,
          userId: resolvedUserId,
          sellerId: dto.sellerId,
          contractNumber: dto.contractNumber,
          saleDate,
          principalAmount,
          financedAmount: schedule.financedAmount,
          downPayment: dto.downPayment,
          interestRate: dto.interestRate,
          totalAmount: schedule.totalAmount,
          termMonths: dto.termMonths,
          paidAmount: dto.downPayment,
          outstandingBalance: schedule.outstandingBalance,
          status: dto.status ?? (schedule.outstandingBalance <= 0 ? SaleStatus.completed : SaleStatus.active),
          notes: dto.notes,
          syncStatus: SyncStatus.pending,
        },
      });

      if (schedule.installments.length > 0) {
        await tx.installment.createMany({
          data: schedule.installments.map((installment) => ({
            saleId: createdSale.id,
            installmentNumber: installment.installmentNumber,
            dueDate: installment.dueDate,
            amount: installment.amount,
            principalAmount: installment.principalAmount,
            interestAmount: installment.interestAmount,
            paidAmount: 0,
            syncStatus: SyncStatus.pending,
          })),
        });
      }

      await tx.product.update({
        where: { id: product.id },
        data: {
          stock: { decrement: 1 },
          syncStatus: SyncStatus.pending,
        },
      });

      return createdSale;
    });

    const created = await this.findOne(sale.id);
    this.realtimeEvents.publishSaleCreated(
      sale.id,
      created.syncId,
      {
        id: sale.id,
        record_sync_id: created.syncId,
        sync_id: created.syncId,
        contractNumber: created.contractNumber ?? undefined,
        clientId: created.clientId,
        productId: created.productId,
        status: created.status,
      },
      'api',
      created.updatedAt.toISOString(),
    );
    console.log('DATA GUARDADA:', created);
    return created;
  }

  async findAll(query: SalesQueryDto) {
    const where = this.buildWhere(query.search);
    if (query.sellerId) {
      where.sellerId = query.sellerId;
    }
    if (query.clientId) {
      where.clientId = query.clientId;
    }
    const [total, items] = await this.prisma.$transaction([
      this.prisma.sale.count({ where }),
      this.prisma.sale.findMany({
        where,
        include: {
          client: true,
          user: true,
          product: true,
          seller: true,
        },
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
    const sale = await this.prisma.sale.findFirst({
      where: { id, deletedAt: null },
      include: {
        client: true,
        user: true,
        product: true,
        seller: true,
        installments: {
          where: { deletedAt: null },
          orderBy: { installmentNumber: 'asc' },
        },
        payments: {
          where: { deletedAt: null },
          orderBy: { paymentDate: 'desc' },
          include: {
            installment: true,
          },
        },
      },
    });

    if (!sale) {
      throw new NotFoundException('Venta no encontrada.');
    }

    return sale;
  }

  async update(id: string, dto: UpdateSaleDto) {
    this.logger.log(`UPDATE sale id=${id} dto=${this.serialize(dto)}`);
    const sale = await this.findOne(id);
    const hasPayments = sale.payments.length > 0;
    const modifiesFinancials = [
      dto.principalAmount,
      dto.downPayment,
      dto.interestRate,
      dto.termMonths,
      dto.productId,
    ].some((value) => value !== undefined);

    if (hasPayments && modifiesFinancials) {
      throw new BadRequestException('No se puede modificar la estructura financiera de una venta con pagos registrados.');
    }

    const productId = dto.productId ?? sale.productId;
    const product = await this.prisma.product.findFirst({ where: { id: productId, deletedAt: null } });
    if (!product) {
      throw new BadRequestException('Producto no encontrado.');
    }

    const principalAmount = dto.principalAmount ?? Number(sale.principalAmount);
    const downPayment = dto.downPayment ?? Number(sale.downPayment);
    const interestRate = dto.interestRate ?? Number(sale.interestRate);
    const termMonths = dto.termMonths ?? sale.termMonths;
    if (downPayment > principalAmount) {
      throw new BadRequestException('La inicial no puede ser mayor que el monto principal.');
    }

    const schedule = this.accountingService.calculateSchedule({
      principalAmount,
      downPayment,
      interestRate,
      termMonths,
      saleDate: new Date(dto.saleDate ?? sale.saleDate.toISOString()),
    });

    await this.prisma.$transaction(async (tx) => {
      if (dto.productId && dto.productId !== sale.productId) {
        await tx.product.update({
          where: { id: sale.productId },
          data: { stock: { increment: 1 }, syncStatus: SyncStatus.pending },
        });
        if (product.stock <= 0) {
          throw new BadRequestException('El nuevo producto no tiene stock disponible.');
        }
        await tx.product.update({
          where: { id: product.id },
          data: { stock: { decrement: 1 }, syncStatus: SyncStatus.pending },
        });
      }

      await tx.sale.update({
        where: { id },
        data: {
          clientId: dto.clientId,
          productId: dto.productId,
          userId: dto.userId,
          sellerId: dto.sellerId,
          contractNumber: dto.contractNumber,
          saleDate: dto.saleDate ? new Date(dto.saleDate) : undefined,
          principalAmount,
          financedAmount: schedule.financedAmount,
          downPayment,
          interestRate,
          totalAmount: schedule.totalAmount,
          termMonths,
          paidAmount: downPayment,
          outstandingBalance: schedule.outstandingBalance,
          status: dto.status ?? (schedule.outstandingBalance <= 0 ? SaleStatus.completed : sale.status),
          notes: dto.notes,
          syncStatus: SyncStatus.pending,
        },
      });

      if (!hasPayments) {
        await tx.installment.updateMany({
          where: { saleId: id, deletedAt: null },
          data: { deletedAt: new Date(), syncStatus: SyncStatus.pending },
        });

        if (schedule.installments.length > 0) {
          await tx.installment.createMany({
            data: schedule.installments.map((installment) => ({
              saleId: id,
              installmentNumber: installment.installmentNumber,
              dueDate: installment.dueDate,
              amount: installment.amount,
              principalAmount: installment.principalAmount,
              interestAmount: installment.interestAmount,
              paidAmount: 0,
              syncStatus: SyncStatus.pending,
            })),
          });
        }
      }
    });

    const updated = await this.findOne(id);
    this.realtimeEvents.publishEntityUpdated({
      entity: 'sale',
      action: 'updated',
      id,
      recordSyncId: updated.syncId,
      data: {
        id,
        record_sync_id: updated.syncId,
        sync_id: updated.syncId,
        contractNumber: updated.contractNumber ?? undefined,
        status: updated.status,
        clientId: updated.clientId,
        productId: updated.productId,
      },
      source: 'api',
      updatedAt: updated.updatedAt.toISOString(),
    });
    return updated;
  }

  async remove(id: string) {
    const sale = await this.findOne(id);
    await this.prisma.$transaction(async (tx) => {
      await tx.payment.updateMany({
        where: { saleId: id, deletedAt: null },
        data: { deletedAt: new Date(), syncStatus: SyncStatus.pending },
      });
      await tx.installment.updateMany({
        where: { saleId: id, deletedAt: null },
        data: { deletedAt: new Date(), syncStatus: SyncStatus.pending },
      });
      await tx.sale.update({
        where: { id },
        data: {
          deletedAt: new Date(),
          status: SaleStatus.cancelled,
          syncStatus: SyncStatus.pending,
        },
      });
      await tx.product.update({
        where: { id: sale.productId },
        data: {
          stock: { increment: 1 },
          syncStatus: SyncStatus.pending,
        },
      });
    });
    this.realtimeEvents.publishEntityUpdated({
      entity: 'sale',
      action: 'deleted',
      id,
      recordSyncId: sale.syncId,
      data: {
        id,
        record_sync_id: sale.syncId,
        sync_id: sale.syncId,
        status: SaleStatus.cancelled,
      },
      source: 'api',
      updatedAt: new Date().toISOString(),
    });
    return { id, removed: true };
  }

  private buildWhere(search?: string): Prisma.SaleWhereInput {
    const normalizedSearch = search?.trim();
    if (!normalizedSearch) {
      return { deletedAt: null };
    }

    const normalizedStatus = this.parseSaleStatus(normalizedSearch);

    return {
      deletedAt: null,
      OR: [
        { contractNumber: { contains: normalizedSearch, mode: 'insensitive' } },
        { notes: { contains: normalizedSearch, mode: 'insensitive' } },
        ...(normalizedStatus ? [{ status: { equals: normalizedStatus } }] : []),
        { client: { firstName: { contains: normalizedSearch, mode: 'insensitive' } } },
        { client: { lastName: { contains: normalizedSearch, mode: 'insensitive' } } },
        { client: { documentId: { contains: normalizedSearch, mode: 'insensitive' } } },
        { client: { phone: { contains: normalizedSearch, mode: 'insensitive' } } },
        { product: { code: { contains: normalizedSearch, mode: 'insensitive' } } },
        { product: { name: { contains: normalizedSearch, mode: 'insensitive' } } },
        { product: { description: { contains: normalizedSearch, mode: 'insensitive' } } },
        { seller: { name: { contains: normalizedSearch, mode: 'insensitive' } } },
        { seller: { documentId: { contains: normalizedSearch, mode: 'insensitive' } } },
        { seller: { phone: { contains: normalizedSearch, mode: 'insensitive' } } },
      ],
    };
  }

  private parseSaleStatus(search: string): SaleStatus | null {
    const normalized = search.trim().toLowerCase();
    switch (normalized) {
      case 'draft':
      case 'borrador':
      case 'apartado':
        return SaleStatus.draft;
      case 'active':
      case 'activa':
      case 'activo':
        return SaleStatus.active;
      case 'completed':
      case 'completada':
      case 'pagada':
      case 'vendida':
        return SaleStatus.completed;
      case 'cancelled':
      case 'cancelada':
        return SaleStatus.cancelled;
      case 'overdue':
      case 'vencida':
        return SaleStatus.overdue;
      default:
        return null;
    }
  }

  private serialize(payload: unknown): string {
    try {
      return JSON.stringify(payload);
    } catch (_) {
      return String(payload);
    }
  }
}