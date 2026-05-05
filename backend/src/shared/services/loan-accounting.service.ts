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

    const installments: InstallmentDraft[] = [];
    const paymentAmount = this.calculateFixedPayment({
      financedAmount,
      interestRate: input.interestRate,
      installmentCount: input.termMonths,
    });
    const fixedInterestAmount = this.calculateFixedMonthlyInterest({
      financedAmount,
      interestRate: input.interestRate,
    });
    const paymentCents = this.toCents(paymentAmount);
    let balanceCents = this.toCents(financedAmount);
    let remainingPlanCents = this.toCents(
      this.calculateTotalFinancingAmount({
        financedAmount,
        interestRate: input.interestRate,
        installmentCount: input.termMonths,
      }),
    );

    for (let index = 1; index <= input.termMonths; index += 1) {
      const openingBalanceCents = balanceCents;
      if (openingBalanceCents <= 0 || remainingPlanCents <= 0) {
        break;
      }

      const isLastInstallment = index === input.termMonths;
      let totalAmountCents = isLastInstallment ? remainingPlanCents : paymentCents;
      if (totalAmountCents > remainingPlanCents) {
        totalAmountCents = remainingPlanCents;
      }

      let interestCents = this.toCents(fixedInterestAmount);
      let principalCents = totalAmountCents - interestCents;

      if (principalCents < 0) {
        principalCents = 0;
        interestCents = totalAmountCents;
      }

      if (principalCents >= openingBalanceCents || isLastInstallment) {
        principalCents = openingBalanceCents;
        interestCents = totalAmountCents - principalCents;
        if (interestCents < 0) {
          interestCents = 0;
          totalAmountCents = principalCents;
        }
      }

      const endingBalanceCents = (principalCents >= openingBalanceCents || isLastInstallment)
        ? 0
        : openingBalanceCents - principalCents;

      installments.push({
        installmentNumber: index,
        dueDate: this.addMonths(input.saleDate, index),
        amount: this.fromCents(totalAmountCents),
        principalAmount: this.fromCents(principalCents),
        interestAmount: this.fromCents(interestCents),
      });

      balanceCents = endingBalanceCents;
      remainingPlanCents = Math.max(remainingPlanCents - totalAmountCents, 0);
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

  private calculateFixedPayment(input: {
    financedAmount: number;
    interestRate: number;
    installmentCount: number;
  }): number {
    if (input.installmentCount <= 0 || input.financedAmount <= 0) {
      return 0;
    }

    return this.roundCurrency(
      this.calculateTotalFinancingAmount(input) / input.installmentCount,
    );
  }

  private calculateFixedMonthlyInterest(input: {
    financedAmount: number;
    interestRate: number;
  }): number {
    if (input.financedAmount <= 0 || input.interestRate <= 0) {
      return 0;
    }

    return this.roundCurrency(input.financedAmount * (input.interestRate / 100));
  }

  private calculateTotalFinancingAmount(input: {
    financedAmount: number;
    interestRate: number;
    installmentCount: number;
  }): number {
    if (input.financedAmount <= 0) {
      return 0;
    }

    const totalInterest = this.roundCurrency(
      this.calculateFixedMonthlyInterest(input) * input.installmentCount,
    );
    return this.roundCurrency(input.financedAmount + totalInterest);
  }

  private addMonths(date: Date, monthsToAdd: number): Date {
    const targetMonthIndex = date.getMonth() + monthsToAdd;
    const targetYear = date.getFullYear() + Math.floor(targetMonthIndex / 12);
    const targetMonth = ((targetMonthIndex % 12) + 12) % 12;
    const maxDay = new Date(targetYear, targetMonth + 1, 0).getDate();
    const targetDay = Math.min(date.getDate(), maxDay);
    return new Date(
      targetYear,
      targetMonth,
      targetDay,
      date.getHours(),
      date.getMinutes(),
      date.getSeconds(),
      date.getMilliseconds(),
    );
  }

  private toCents(value: number): number {
    return Math.round(value * 100);
  }

  private fromCents(value: number): number {
    return value / 100;
  }
}