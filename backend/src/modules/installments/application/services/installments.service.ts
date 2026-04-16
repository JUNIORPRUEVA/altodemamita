import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SyncStatus } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { LoanAccountingService } from 'src/shared/services/loan-accounting.service';
import { CreateInstallmentDto } from '../dto/create-installment.dto';
import { ListInstallmentsDto } from '../dto/list-installments.dto';
import { UpdateInstallmentDto } from '../dto/update-installment.dto';

@Injectable()
export class InstallmentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly accountingService: LoanAccountingService,
  ) {}

  async create(dto: CreateInstallmentDto) {
    await this.ensureSale(dto.saleId);
    await this.ensureUniqueInstallmentNumber(dto.saleId, dto.installmentNumber);

    const installment = await this.prisma.installment.create({
      data: {
        saleId: dto.saleId,
        installmentNumber: dto.installmentNumber,
        dueDate: new Date(dto.dueDate),
        amount: dto.amount,
        principalAmount: dto.principalAmount,
        interestAmount: dto.interestAmount,
        status: dto.status,
        syncStatus: SyncStatus.pending,
      },
    });

    await this.accountingService.syncSaleAggregates(this.prisma, dto.saleId);
    return this.findOne(installment.id);
  }

  async findAll(query: ListInstallmentsDto) {
    const where: Prisma.InstallmentWhereInput = {
      deletedAt: null,
      saleId: query.saleId,
      status: query.status as never,
      OR: query.search
        ? [
            { sale: { contractNumber: { contains: query.search, mode: 'insensitive' } } },
            { sale: { client: { firstName: { contains: query.search, mode: 'insensitive' } } } },
            { sale: { client: { lastName: { contains: query.search, mode: 'insensitive' } } } },
          ]
        : undefined,
    };

    const [total, items] = await this.prisma.$transaction([
      this.prisma.installment.count({ where }),
      this.prisma.installment.findMany({
        where,
        include: {
          sale: {
            include: {
              client: true,
            },
          },
        },
        orderBy: [{ dueDate: 'asc' }, { installmentNumber: 'asc' }],
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
    const installment = await this.prisma.installment.findFirst({
      where: { id, deletedAt: null },
      include: {
        sale: {
          include: {
            client: true,
            product: true,
          },
        },
        payments: {
          where: { deletedAt: null },
        },
      },
    });
    if (!installment) {
      throw new NotFoundException('Cuota no encontrada.');
    }
    return installment;
  }

  async update(id: string, dto: UpdateInstallmentDto) {
    const installment = await this.findOne(id);
    if (dto.installmentNumber && dto.installmentNumber !== installment.installmentNumber) {
      await this.ensureUniqueInstallmentNumber(installment.saleId, dto.installmentNumber, id);
    }

    if (dto.amount !== undefined && dto.amount < Number(installment.paidAmount)) {
      throw new BadRequestException('El monto de la cuota no puede ser menor al ya pagado.');
    }

    await this.prisma.installment.update({
      where: { id },
      data: {
        saleId: dto.saleId,
        installmentNumber: dto.installmentNumber,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
        amount: dto.amount,
        principalAmount: dto.principalAmount,
        interestAmount: dto.interestAmount,
        status: dto.status,
        syncStatus: SyncStatus.pending,
      },
    });

    await this.accountingService.syncSaleAggregates(this.prisma, installment.saleId);
    return this.findOne(id);
  }

  async remove(id: string) {
    const installment = await this.findOne(id);
    await this.prisma.installment.update({
      where: { id },
      data: {
        deletedAt: new Date(),
        syncStatus: SyncStatus.pending,
      },
    });
    await this.accountingService.syncSaleAggregates(this.prisma, installment.saleId);
    return { id, removed: true };
  }

  private async ensureSale(saleId: string) {
    const sale = await this.prisma.sale.findFirst({ where: { id: saleId, deletedAt: null } });
    if (!sale) {
      throw new BadRequestException('Venta no encontrada.');
    }
  }

  private async ensureUniqueInstallmentNumber(saleId: string, installmentNumber: number, id?: string) {
    const existing = await this.prisma.installment.findFirst({
      where: {
        saleId,
        installmentNumber,
        deletedAt: null,
        id: id ? { not: id } : undefined,
      },
    });

    if (existing) {
      throw new BadRequestException('La venta ya tiene una cuota con ese número.');
    }
  }
}