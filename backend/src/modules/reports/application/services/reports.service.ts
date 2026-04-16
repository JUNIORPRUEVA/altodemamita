import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { PrismaService } from 'src/infrastructure/prisma/prisma.service';
import { ReportRangeDto } from '../dto/report-range.dto';

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async getSummary() {
    const [clients, products, sales, overdueInstallments, payments] = await this.prisma.$transaction([
      this.prisma.client.count({ where: { deletedAt: null } }),
      this.prisma.product.count({ where: { deletedAt: null } }),
      this.prisma.sale.findMany({ where: { deletedAt: null } }),
      this.prisma.installment.count({ where: { deletedAt: null, status: 'overdue' } }),
      this.prisma.payment.aggregate({
        where: { deletedAt: null },
        _sum: { amount: true },
      }),
    ]);

    const totalPortfolio = sales.reduce((sum, sale) => sum + Number(sale.totalAmount), 0);
    const outstanding = sales.reduce((sum, sale) => sum + Number(sale.outstandingBalance), 0);

    return {
      clients,
      products,
      activeSales: sales.filter((sale) => sale.status === 'active').length,
      overdueSales: sales.filter((sale) => sale.status === 'overdue').length,
      completedSales: sales.filter((sale) => sale.status === 'completed').length,
      overdueInstallments,
      totalPortfolio,
      outstanding,
      totalCollected: Number(payments._sum.amount ?? 0),
    };
  }

  async getSalesReport(query: ReportRangeDto) {
    const where = this.buildSaleWhere(query);
    return this.prisma.sale.findMany({
      where,
      include: {
        client: true,
        user: true,
        product: true,
        installments: { where: { deletedAt: null } },
        payments: { where: { deletedAt: null } },
      },
      orderBy: { saleDate: 'desc' },
    });
  }

  async getPaymentsReport(query: ReportRangeDto) {
    const where: Prisma.PaymentWhereInput = {
      deletedAt: null,
      saleId: query.saleId,
      method: query.method as never,
      paymentDate: this.buildDateRange(query),
      sale: query.clientId ? { clientId: query.clientId } : undefined,
    };

    return this.prisma.payment.findMany({
      where,
      include: {
        sale: {
          include: {
            client: true,
            product: true,
          },
        },
        installment: true,
      },
      orderBy: { paymentDate: 'desc' },
    });
  }

  async getDelinquencyReport(query: ReportRangeDto) {
    return this.prisma.installment.findMany({
      where: {
        deletedAt: null,
        status: 'overdue',
        dueDate: this.buildDateRange(query),
        sale: query.clientId ? { clientId: query.clientId } : undefined,
      },
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
      orderBy: { dueDate: 'asc' },
    });
  }

  private buildSaleWhere(query: ReportRangeDto): Prisma.SaleWhereInput {
    return {
      deletedAt: null,
      clientId: query.clientId,
      status: query.status as never,
      saleDate: this.buildDateRange(query),
    };
  }

  private buildDateRange(query: ReportRangeDto): Prisma.DateTimeFilter | undefined {
    if (!query.from && !query.to) {
      return undefined;
    }

    return {
      gte: query.from ? new Date(query.from) : undefined,
      lte: query.to ? new Date(query.to) : undefined,
    };
  }
}