import { Injectable } from '@nestjs/common';
import { InstallmentStatus, Prisma, PrismaClient, SaleStatus, SyncStatus } from '@prisma/client';

type PrismaExecutor = PrismaClient | Prisma.TransactionClient;

interface ScheduleInput {
  principalAmount: number;
  downPayment: number;
  interestRate: number;
  termMonths: number;
  saleDate: Date;
}

interface InstallmentDraft {
  installmentNumber: number;
  dueDate: Date;
  amount: number;
  principalAmount: number;
  interestAmount: number;
}

@Injectable()
export class LoanAccountingService {
  calculateSchedule(input: ScheduleInput): {
    financedAmount: number;
    totalAmount: number;
    outstandingBalance: number;
    installments: InstallmentDraft[];
  } {
    const financedAmount = this.roundCurrency(input.principalAmount - input.downPayment);
    if (financedAmount <= 0 || input.termMonths <= 0) {
      return {
        financedAmount: Math.max(financedAmount, 0),
        totalAmount: this.roundCurrency(input.downPayment),
        outstandingBalance: 0,
        installments: [],
      };
    }

    const monthlyRate = input.interestRate / 100;
    const installmentAmount = monthlyRate === 0
      ? financedAmount / input.termMonths
      : (financedAmount * monthlyRate) / (1 - Math.pow(1 + monthlyRate, -input.termMonths));

    const installments: InstallmentDraft[] = [];
    let balance = financedAmount;

    for (let index = 1; index <= input.termMonths; index += 1) {
      const interestAmount = this.roundCurrency(balance * monthlyRate);
      let principalAmount = this.roundCurrency(installmentAmount - interestAmount);
      let amount = this.roundCurrency(installmentAmount);

      if (index === input.termMonths) {
        principalAmount = this.roundCurrency(balance);
        amount = this.roundCurrency(principalAmount + interestAmount);
      }

      installments.push({
        installmentNumber: index,
        dueDate: this.addMonths(input.saleDate, index),
        amount,
        principalAmount,
        interestAmount,
      });

      balance = this.roundCurrency(balance - principalAmount);
    }

    const totalInstallments = this.roundCurrency(
      installments.reduce((sum, installment) => sum + installment.amount, 0),
    );

    return {
      financedAmount,
      totalAmount: this.roundCurrency(input.downPayment + totalInstallments),
      outstandingBalance: totalInstallments,
      installments,
    };
  }

  async syncSaleAggregates(prisma: PrismaExecutor, saleId: string): Promise<void> {
    const sale = await prisma.sale.findFirst({
      where: { id: saleId, deletedAt: null },
      include: {
        installments: {
          where: { deletedAt: null },
          orderBy: { installmentNumber: 'asc' },
        },
        payments: {
          where: { deletedAt: null },
        },
      },
    });

    if (!sale) {
      return;
    }

    const paymentTotalsByInstallment = new Map<string, number>();
    for (const payment of sale.payments) {
      if (payment.installmentId) {
        paymentTotalsByInstallment.set(
          payment.installmentId,
          this.roundCurrency((paymentTotalsByInstallment.get(payment.installmentId) ?? 0) + Number(payment.amount)),
        );
      }
    }

    for (const installment of sale.installments) {
      const paidAmount = this.roundCurrency(paymentTotalsByInstallment.get(installment.id) ?? 0);
      const amount = Number(installment.amount);
      let status: InstallmentStatus = InstallmentStatus.pending;

      if (paidAmount >= amount) {
        status = InstallmentStatus.paid;
      } else if (paidAmount > 0) {
        status = InstallmentStatus.partial;
      } else if (installment.dueDate < new Date()) {
        status = InstallmentStatus.overdue;
      }

      await prisma.installment.update({
        where: { id: installment.id },
        data: {
          paidAmount,
          status,
          syncStatus: SyncStatus.pending,
        },
      });
    }

    const refreshedInstallments = await prisma.installment.findMany({
      where: { saleId, deletedAt: null },
    });
    const scheduledAmount = this.roundCurrency(
      refreshedInstallments.reduce((sum, installment) => sum + Number(installment.amount), 0),
    );
    const paymentAmount = this.roundCurrency(
      sale.payments.reduce((sum, payment) => sum + Number(payment.amount), 0),
    );
    const totalAmount = this.roundCurrency(Number(sale.downPayment) + scheduledAmount);
    const paidAmount = this.roundCurrency(Number(sale.downPayment) + paymentAmount);
    const outstandingBalance = this.roundCurrency(Math.max(totalAmount - paidAmount, 0));

    let status: SaleStatus = SaleStatus.active;
    if (sale.deletedAt) {
      status = SaleStatus.cancelled;
    } else if (outstandingBalance <= 0) {
      status = SaleStatus.completed;
    } else if (refreshedInstallments.some((installment) => installment.status === InstallmentStatus.overdue)) {
      status = SaleStatus.overdue;
    }

    await prisma.sale.update({
      where: { id: saleId },
      data: {
        totalAmount,
        paidAmount,
        outstandingBalance,
        status,
        syncStatus: SyncStatus.pending,
      },
    });
  }

  roundCurrency(value: number): number {
    return Math.round((value + Number.EPSILON) * 100) / 100;
  }

  private addMonths(date: Date, monthsToAdd: number): Date {
    return new Date(
      date.getFullYear(),
      date.getMonth() + monthsToAdd,
      date.getDate(),
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
      date.getMilliseconds(),
    );
  }
}