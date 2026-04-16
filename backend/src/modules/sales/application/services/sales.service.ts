import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SaleStatus, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { RealtimeEventsService } from 'src/modules/realtime/realtime-events.service';
import { PaginationQueryDto } from 'src/shared/dto/pagination-query.dto';
import { LoanAccountingService } from 'src/shared/services/loan-accounting.service';
import { CreateSaleDto } from '../dto/create-sale.dto';
import { UpdateSaleDto } from '../dto/update-sale.dto';

@Injectable()
export class SalesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
    private readonly realtimeEvents: RealtimeEventsService,
  ) {}

  async create(dto: CreateSaleDto, actorUserId: string) {
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
    return created;
  }

  async findAll(query: PaginationQueryDto) {
    const where = this.buildWhere(query.search);
    const [total, items] = await this.prisma.$transaction([
      this.prisma.sale.count({ where }),
      this.prisma.sale.findMany({
        where,
        include: {
          client: true,
          user: true,
          product: true,
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
        installments: {
          where: { deletedAt: null },
          orderBy: { installmentNumber: 'asc' },
        },
        payments: {
          where: { deletedAt: null },
          orderBy: { paymentDate: 'desc' },
        },
      },
    });

    if (!sale) {
      throw new NotFoundException('Venta no encontrada.');
    }

    return sale;
  }

  async update(id: string, dto: UpdateSaleDto) {
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
    if (!search?.trim()) {
      return { deletedAt: null };
    }

    return {
      deletedAt: null,
      OR: [
        { contractNumber: { contains: search, mode: 'insensitive' } },
        { notes: { contains: search, mode: 'insensitive' } },
        { status: { equals: search as SaleStatus } },
        { client: { firstName: { contains: search, mode: 'insensitive' } } },
        { client: { lastName: { contains: search, mode: 'insensitive' } } },
        { product: { name: { contains: search, mode: 'insensitive' } } },
      ],
    };
  }
}