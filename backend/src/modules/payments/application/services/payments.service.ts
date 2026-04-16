import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { RealtimeEventsService } from 'src/modules/realtime/realtime-events.service';
import { LoanAccountingService } from 'src/shared/services/loan-accounting.service';
import { CreatePaymentDto } from '../dto/create-payment.dto';
import { ListPaymentsDto } from '../dto/list-payments.dto';
import { UpdatePaymentDto } from '../dto/update-payment.dto';

@Injectable()
export class PaymentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
    private readonly realtimeEvents: RealtimeEventsService,
  ) {}

  async create(dto: CreatePaymentDto) {
    const sale = await this.ensureSale(dto.saleId);
    const installment = dto.installmentId ? await this.ensureInstallment(dto.installmentId, dto.saleId) : null;
    const split = await this.resolvePaymentSplit(dto, installment?.id);

    const payment = await this.prisma.payment.create({
      data: {
        saleId: dto.saleId,
        installmentId: dto.installmentId,
        paymentDate: new Date(dto.paymentDate),
        amount: dto.amount,
        principalAmount: split.principalAmount,
        interestAmount: split.interestAmount,
        method: dto.method,
        reference: dto.reference,
        notes: dto.notes,
        syncStatus: SyncStatus.pending,
      },
    });

    await this.accountingService.syncSaleAggregates(this.prisma, sale.id);
    const created = await this.findOne(payment.id);
    this.realtimeEvents.publishPaymentCreated(
      payment.id,
      created.syncId,
      {
        id: payment.id,
        record_sync_id: created.syncId,
        sync_id: created.syncId,
        saleId: created.saleId,
        installmentId: created.installmentId ?? undefined,
        amount: Number(created.amount),
        method: created.method,
      },
      'api',
      created.updatedAt.toISOString(),
    );
    return created;
  }

  async findAll(query: ListPaymentsDto) {
    const where: Prisma.PaymentWhereInput = {
      deletedAt: null,
      saleId: query.saleId,
      method: query.method as never,
      OR: query.search
        ? [
            { reference: { contains: query.search, mode: 'insensitive' } },
            { notes: { contains: query.search, mode: 'insensitive' } },
            { sale: { contractNumber: { contains: query.search, mode: 'insensitive' } } },
            { sale: { client: { firstName: { contains: query.search, mode: 'insensitive' } } } },
            { sale: { client: { lastName: { contains: query.search, mode: 'insensitive' } } } },
          ]
        : undefined,
    };

    const [total, items] = await this.prisma.$transaction([
      this.prisma.payment.count({ where }),
      this.prisma.payment.findMany({
        where,
        include: {
          sale: {
            include: {
              client: true,
            },
          },
          installment: true,
        },
        orderBy: { paymentDate: 'desc' },
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
    const payment = await this.prisma.payment.findFirst({
      where: { id, deletedAt: null },
      include: {
        sale: {
          include: {
            client: true,
            product: true,
          },
        },
        installment: true,
      },
    });
    if (!payment) {
      throw new NotFoundException('Pago no encontrado.');
    }
    return payment;
  }

  async update(id: string, dto: UpdatePaymentDto) {
    const payment = await this.findOne(id);
    const installmentId = dto.installmentId ?? payment.installmentId ?? undefined;
    if (installmentId) {
      await this.ensureInstallment(installmentId, payment.saleId);
    }
    const split = await this.resolvePaymentSplit(
      {
        ...dto,
        saleId: payment.saleId,
        amount: dto.amount ?? Number(payment.amount),
        method: dto.method ?? payment.method,
        paymentDate: dto.paymentDate ?? payment.paymentDate.toISOString(),
      } as CreatePaymentDto,
      installmentId,
    );

    await this.prisma.payment.update({
      where: { id },
      data: {
        installmentId,
        paymentDate: dto.paymentDate ? new Date(dto.paymentDate) : undefined,
        amount: dto.amount,
        principalAmount: split.principalAmount,
        interestAmount: split.interestAmount,
        method: dto.method,
        reference: dto.reference,
        notes: dto.notes,
        syncStatus: SyncStatus.pending,
      },
    });

    await this.accountingService.syncSaleAggregates(this.prisma, payment.saleId);
    const updated = await this.findOne(id);
    this.realtimeEvents.publishEntityUpdated({
      entity: 'payment',
      action: 'updated',
      id,
      recordSyncId: updated.syncId,
      data: {
        id,
        record_sync_id: updated.syncId,
        sync_id: updated.syncId,
        saleId: updated.saleId,
        installmentId: updated.installmentId ?? undefined,
        amount: Number(updated.amount),
        method: updated.method,
      },
      source: 'api',
      updatedAt: updated.updatedAt.toISOString(),
    });
    return updated;
  }

  async remove(id: string) {
    const payment = await this.findOne(id);
    await this.prisma.payment.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.pending,
      },
    });
    await this.accountingService.syncSaleAggregates(this.prisma, payment.saleId);
    this.realtimeEvents.publishEntityUpdated({
      entity: 'payment',
      action: 'deleted',
      id,
      recordSyncId: payment.syncId,
      data: {
        id,
        record_sync_id: payment.syncId,
        sync_id: payment.syncId,
        saleId: payment.saleId,
      },
      source: 'api',
      updatedAt: new Date().toISOString(),
    });
    return { id, removed: true };
  }

  private async ensureSale(saleId: string) {
    const sale = await this.prisma.sale.findFirst({ where: { id: saleId, deletedAt: null } });
    if (!sale) {
      throw new BadRequestException('Venta no encontrada.');
    }
    return sale;
  }

  private async ensureInstallment(installmentId: string, saleId: string) {
    const installment = await this.prisma.installment.findFirst({
      where: { id: installmentId, saleId, deletedAt: null },
    });
    if (!installment) {
      throw new BadRequestException('Cuota no encontrada para la venta indicada.');
    }
    return installment;
  }

  private async resolvePaymentSplit(dto: CreatePaymentDto, installmentId?: string) {
    if (dto.principalAmount !== undefined || dto.interestAmount !== undefined) {
      const principalAmount = dto.principalAmount ?? dto.amount - (dto.interestAmount ?? 0);
      const interestAmount = dto.interestAmount ?? dto.amount - principalAmount;
      if (this.round(principalAmount + interestAmount) !== this.round(dto.amount)) {
        throw new BadRequestException('La suma de principal e interés debe ser igual al monto del pago.');
      }
      return { principalAmount, interestAmount };
    }

    if (!installmentId) {
      return { principalAmount: dto.amount, interestAmount: 0 };
    }

    const installment = await this.prisma.installment.findUnique({ where: { id: installmentId } });
    if (!installment) {
      throw new BadRequestException('Cuota no encontrada.');
    }

    const payments = await this.prisma.payment.findMany({
      where: { installmentId, deletedAt: null },
    });
    const paidInterest = this.round(payments.reduce((sum, payment) => sum + Number(payment.interestAmount), 0));
    const remainingInterest = Math.max(this.round(Number(installment.interestAmount) - paidInterest), 0);
    const interestAmount = Math.min(dto.amount, remainingInterest);
    const principalAmount = this.round(dto.amount - interestAmount);

    return { principalAmount, interestAmount };
  }

  private round(value: number) {
    return Math.round((value + Number.EPSILON) * 100) / 100;
  }
}