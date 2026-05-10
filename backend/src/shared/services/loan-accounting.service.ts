import { Injectable } from "@nestjs/common";
import {
  InstallmentStatus,
  Prisma,
  PrismaClient,
  SaleStatus,
  SyncStatus,
} from "@prisma/client";

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
  openingBalance: number;
  endingBalance: number;
  principalAmount: number;
  interestAmount: number;
  status: InstallmentStatus;
}

@Injectable()
export class LoanAccountingService {
  calculateSchedule(input: ScheduleInput): {
    financedAmount: number;
    totalAmount: number;
    outstandingBalance: number;
    installments: InstallmentDraft[];
  } {
    const financedAmount = this.roundCurrency(
      input.principalAmount - input.downPayment,
    );
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
    const rateDecimal = this.normalizeRate(input.interestRate);
    let balance = financedAmount;

    for (let index = 1; index <= input.termMonths; index += 1) {
      const openingBalance = balance;
      if (openingBalance <= 0) {
        break;
      }

      const interestAmount = this.roundCurrency(openingBalance * rateDecimal);
      const principalAmount = paymentAmount - interestAmount;
      const rawEndingBalance = openingBalance - principalAmount;
      const endingBalance = rawEndingBalance < 0.01 ? 0 : rawEndingBalance;

      const dueDate = this.addMonths(input.saleDate, index);

      installments.push({
        installmentNumber: index,
        dueDate,
        amount: paymentAmount,
        openingBalance,
        endingBalance,
        principalAmount,
        interestAmount,
        status: this.resolveInstallmentStatus({
          dueDate,
          paidAmount: 0,
          amount: paymentAmount,
          asOf: new Date(),
        }),
      });

      balance = endingBalance;
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

  async syncSaleAggregates(
    prisma: PrismaExecutor,
    saleId: string,
  ): Promise<void> {
    const sale = await prisma.sale.findFirst({
      where: { id: saleId, deletedAt: null },
      include: {
        installments: {
          where: { deletedAt: null },
          orderBy: { installmentNumber: "asc" },
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
          this.roundCurrency(
            (paymentTotalsByInstallment.get(payment.installmentId) ?? 0) +
              Number(payment.amount),
          ),
        );
      }
    }

    for (const installment of sale.installments) {
      const paidAmount = this.roundCurrency(
        paymentTotalsByInstallment.get(installment.id) ?? 0,
      );
      const amount = Number(installment.amount);
      let status: InstallmentStatus = InstallmentStatus.pending;

      if (paidAmount >= amount) {
        status = InstallmentStatus.paid;
      } else if (paidAmount > 0) {
        status = InstallmentStatus.partial;
      } else if (this.isPastDue(installment.dueDate, new Date())) {
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
      refreshedInstallments.reduce(
        (sum, installment) => sum + Number(installment.amount),
        0,
      ),
    );
    const paymentAmount = this.roundCurrency(
      sale.payments.reduce((sum, payment) => sum + Number(payment.amount), 0),
    );
    const totalAmount = this.roundCurrency(
      Number(sale.downPayment) + scheduledAmount,
    );
    const paidAmount = this.roundCurrency(
      Number(sale.downPayment) + paymentAmount,
    );
    const outstandingBalance = this.roundCurrency(
      Math.max(totalAmount - paidAmount, 0),
    );

    let status: SaleStatus = SaleStatus.active;
    if (sale.deletedAt) {
      status = SaleStatus.cancelled;
    } else if (outstandingBalance <= 0) {
      status = SaleStatus.completed;
    } else if (
      refreshedInstallments.some((installment) => {
        const remaining = this.roundCurrency(
          Number(installment.amount) - Number(installment.paidAmount),
        );
        return remaining > 0.009 && this.isPastDue(installment.dueDate, new Date());
      })
    ) {
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

    const rateDecimal = this.normalizeRate(input.interestRate);
    if (rateDecimal <= 0) {
      return input.financedAmount / input.installmentCount;
    }

    const denominator = 1 - Math.pow(1 + rateDecimal, -input.installmentCount);
    if (Math.abs(denominator) < Number.EPSILON) {
      return input.financedAmount / input.installmentCount;
    }

    return (input.financedAmount * rateDecimal) / denominator;
  }

  private calculateTotalFinancingAmount(input: {
    financedAmount: number;
    interestRate: number;
    installmentCount: number;
  }): number {
    if (input.financedAmount <= 0) {
      return 0;
    }

    return this.roundCurrency(
      this.calculateFixedPayment(input) * input.installmentCount,
    );
  }

  private normalizeRate(ratePercent: number): number {
    if (ratePercent <= 0) {
      return 0;
    }

    return ratePercent / 100;
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

  private resolveInstallmentStatus(input: {
    dueDate: Date;
    paidAmount: number;
    amount: number;
    asOf: Date;
  }): InstallmentStatus {
    if (input.paidAmount >= input.amount) {
      return InstallmentStatus.paid;
    }
    if (input.paidAmount > 0) {
      return InstallmentStatus.partial;
    }
    return this.isPastDue(input.dueDate, input.asOf)
      ? InstallmentStatus.overdue
      : InstallmentStatus.pending;
  }

  private isPastDue(dueDate: Date, asOf: Date): boolean {
    const dueDay = new Date(
      dueDate.getFullYear(),
      dueDate.getMonth(),
      dueDate.getDate(),
    ).getTime();
    const today = new Date(
      asOf.getFullYear(),
      asOf.getMonth(),
      asOf.getDate(),
    ).getTime();
    return dueDay < today;
  }

}
