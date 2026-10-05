import { Prisma } from '@prisma/client';
import {
  BUSINESS_TIMEZONE,
  dateKeyInTimeZone,
  differenceInCalendarDays,
} from './installmentStatus.service';

export const PAYMENT_REMINDER_TYPE = 'OVERDUE_INSTALLMENTS';
export const DEFAULT_TIMEZONE = BUSINESS_TIMEZONE;
export const DEFAULT_LATE_FEE_ENABLED = true;
export const DEFAULT_LATE_FEE_DAILY_RATE = '0.005';
export const DEFAULT_LATE_FEE_GRACE_DAYS = 5;

const CURRENCY_SCALE = 2;

export type LateFeeInstallmentInput = {
  id?: string;
  syncId: string;
  saleSyncId?: string | null;
  installmentNumber?: number | null;
  dueDate?: Date | null;
  principalAmount?: Prisma.Decimal | number | string | null;
  interestAmount?: Prisma.Decimal | number | string | null;
  totalAmount?: Prisma.Decimal | number | string | null;
  paidPrincipalAmount?: Prisma.Decimal | number | string | null;
  paidInterestAmount?: Prisma.Decimal | number | string | null;
  paidAmount?: Prisma.Decimal | number | string | null;
  status?: string | null;
  deletedAt?: Date | null;
};

export type LateFeePaymentInput = {
  installmentSyncId?: string | null;
  paidAt?: Date | null;
  amount?: Prisma.Decimal | number | string | null;
  principalApplied?: Prisma.Decimal | number | string | null;
  interestApplied?: Prisma.Decimal | number | string | null;
  lateFeeApplied?: Prisma.Decimal | number | string | null;
  deletedAt?: Date | null;
};

export type LateFeeSaleContext = {
  companyId?: string;
  clienteId?: string | null;
  clientSyncId?: string | null;
  clienteNombre?: string | null;
  clienteTelefono?: string | null;
  ventaId?: string | null;
  saleSyncId: string;
  lotLabel?: string | null;
};

export type LateFeeInstallmentSummary = {
  cuotaId: string;
  cuotaSyncId: string;
  numeroCuota: number | null;
  fechaVencimiento: string;
  montoOriginal: string;
  montoPagado: string;
  saldoPendiente: string;
  interesPendiente?: string;
  capitalPendiente?: string;
  diasAtraso: number;
  diasGracia?: number;
  diasMora?: number;
  tasaDiaria: string;
  mora: string;
  totalActualizado: string;
};

export type LateFeeSummary = {
  companyId: string | null;
  clienteId: string | null;
  clienteSyncId: string | null;
  ventaId: string | null;
  ventaSyncId: string;
  fechaCalculo: string;
  cantidadCuotasVencidas: number;
  capitalPendiente: string;
  moraTotal: string;
  totalGeneral: string;
  ultimaCuotaVencidaSyncId: string | null;
  periodoNotificacion: string | null;
  cuotas: LateFeeInstallmentSummary[];
};

export class LateFeeCalculationService {
  constructor(
    private readonly options: {
      enabled?: boolean;
      dailyRate?: Prisma.Decimal | number | string;
      graceDays?: number;
      timezone?: string;
    } = {},
  ) {}

  calculateSaleSummary(input: {
    context: LateFeeSaleContext;
    installments: LateFeeInstallmentInput[];
    payments?: LateFeePaymentInput[];
    calculationDate?: Date;
  }): LateFeeSummary {
    const calculationDate = input.calculationDate ?? new Date();
    const timezone = this.options.timezone ?? DEFAULT_TIMEZONE;
    const enabled = this.options.enabled ?? DEFAULT_LATE_FEE_ENABLED;
    const dailyRate = decimal(this.options.dailyRate ?? DEFAULT_LATE_FEE_DAILY_RATE);
    const graceDays = normalizeGraceDays(this.options.graceDays ?? DEFAULT_LATE_FEE_GRACE_DAYS);
    const calculationDateKey = dateKeyInTimeZone(calculationDate, timezone);
    const paymentHistoryByInstallment = groupPayments(input.payments ?? []);
    const summaries = input.installments
      .filter((installment) => isCandidateInstallment(installment))
      .map((installment): LateFeeInstallmentSummary | null => {
        const dueDate = installment.dueDate;
        if (!dueDate) return null;
        const dueDateKey = dateKeyInTimeZone(dueDate, timezone);
        const overdueDays = differenceInCalendarDays(calculationDateKey, dueDateKey);
        if (overdueDays <= 0) return null;

        const balances = installmentBalances(installment);
        const installmentAmount = balances.originalAmount;
        const paidAmount = balances.paidAmount;
        const pendingAmount = balances.outstandingAmount;
        if (pendingAmount.lte(0)) return null;

        const historicalFee = calculateHistoricalLateFee({
          originalAmount: installmentAmount,
          paidAmount,
          dueDateKey,
          calculationDateKey,
          dailyRate,
          graceDays,
          enabled,
          payments: paymentHistoryByInstallment.get(installment.syncId) ?? [],
          timezone,
        });
        const lateFeeDays = enabled ? Math.max(0, overdueDays - graceDays) : 0;
        const lateFee = historicalFee ?? money(pendingAmount.mul(dailyRate).mul(lateFeeDays));
        const total = money(pendingAmount.plus(lateFee));

        return {
          cuotaId: installment.id ?? installment.syncId,
          cuotaSyncId: installment.syncId,
          numeroCuota: installment.installmentNumber ?? null,
          fechaVencimiento: dueDateKey,
          montoOriginal: formatDecimal(installmentAmount),
          montoPagado: formatDecimal(paidAmount),
          saldoPendiente: formatDecimal(pendingAmount),
          interesPendiente: formatDecimal(balances.interestOutstanding),
          capitalPendiente: formatDecimal(balances.principalOutstanding),
          diasAtraso: overdueDays,
          diasGracia: graceDays,
          diasMora: lateFeeDays,
          tasaDiaria: dailyRate.toString(),
          mora: formatDecimal(lateFee),
          totalActualizado: formatDecimal(total),
        };
      })
      .filter((value): value is LateFeeInstallmentSummary => Boolean(value))
      .sort((a, b) => {
        if (a.fechaVencimiento !== b.fechaVencimiento) {
          return a.fechaVencimiento.localeCompare(b.fechaVencimiento);
        }
        return (a.numeroCuota ?? 0) - (b.numeroCuota ?? 0);
      });

    const capital = summaries.reduce((total, cuota) => total.plus(cuota.saldoPendiente), decimal(0));
    const lateFeeTotal = summaries.reduce((total, cuota) => total.plus(cuota.mora), decimal(0));
    const latest = [...summaries].sort((a, b) => {
      if (a.fechaVencimiento !== b.fechaVencimiento) {
        return b.fechaVencimiento.localeCompare(a.fechaVencimiento);
      }
      return (b.numeroCuota ?? 0) - (a.numeroCuota ?? 0);
    })[0];

    return {
      companyId: input.context.companyId ?? null,
      clienteId: input.context.clienteId ?? null,
      clienteSyncId: input.context.clientSyncId ?? null,
      ventaId: input.context.ventaId ?? null,
      ventaSyncId: input.context.saleSyncId,
      fechaCalculo: calculationDateKey,
      cantidadCuotasVencidas: summaries.length,
      capitalPendiente: formatDecimal(money(capital)),
      moraTotal: formatDecimal(money(lateFeeTotal)),
      totalGeneral: formatDecimal(money(capital.plus(lateFeeTotal))),
      ultimaCuotaVencidaSyncId: latest?.cuotaSyncId ?? null,
      periodoNotificacion: latest?.fechaVencimiento.slice(0, 7) ?? null,
      cuotas: summaries,
    };
  }
}

function isCandidateInstallment(installment: LateFeeInstallmentInput) {
  if (installment.deletedAt) return false;
  const status = normalizeStatus(installment.status);
  return status !== 'pagada' && status !== 'cancelada' && status !== 'ajustada';
}

function normalizeStatus(status?: string | null) {
  return String(status ?? '').trim().toLowerCase();
}

function groupPayments(payments: LateFeePaymentInput[]) {
  const grouped = new Map<string, LateFeePaymentInput[]>();
  for (const payment of payments) {
    if (payment.deletedAt || !payment.installmentSyncId || !payment.paidAt) continue;
    const items = grouped.get(payment.installmentSyncId) ?? [];
    items.push(payment);
    grouped.set(payment.installmentSyncId, items);
  }
  for (const items of grouped.values()) {
    items.sort((a, b) => (a.paidAt?.getTime() ?? 0) - (b.paidAt?.getTime() ?? 0));
  }
  return grouped;
}

function calculateHistoricalLateFee(input: {
  originalAmount: Prisma.Decimal;
  paidAmount: Prisma.Decimal;
  dueDateKey: string;
  calculationDateKey: string;
  dailyRate: Prisma.Decimal;
  graceDays: number;
  enabled: boolean;
  payments: LateFeePaymentInput[];
  timezone: string;
}) {
  if (!input.enabled) return money(0);
  if (input.payments.length === 0 || input.paidAmount.lte(0)) return null;

  let remainingAmount = input.originalAmount;
  let unallocatedPaidAmount = input.paidAmount;
  const graceEndDateKey = addCalendarDays(input.dueDateKey, input.graceDays);
  let cursorDateKey = graceEndDateKey;
  let totalFee = decimal(0);

  for (const payment of input.payments) {
    if (!payment.paidAt || unallocatedPaidAmount.lte(0)) break;
    const paymentDateKey = dateKeyInTimeZone(payment.paidAt, input.timezone);
    if (paymentDateKey <= graceEndDateKey) {
      const amount = minDecimal(paymentOutstandingAmount(payment), unallocatedPaidAmount);
      remainingAmount = maxDecimal(remainingAmount.minus(amount), decimal(0));
      unallocatedPaidAmount = maxDecimal(unallocatedPaidAmount.minus(amount), decimal(0));
      continue;
    }
    if (paymentDateKey > input.calculationDateKey) continue;

    const days = differenceInCalendarDays(paymentDateKey, cursorDateKey);
    if (days > 0 && remainingAmount.gt(0)) {
      totalFee = totalFee.plus(remainingAmount.mul(input.dailyRate).mul(days));
    }

    const appliedPayment = minDecimal(paymentOutstandingAmount(payment), unallocatedPaidAmount);
    remainingAmount = maxDecimal(remainingAmount.minus(appliedPayment), decimal(0));
    unallocatedPaidAmount = maxDecimal(unallocatedPaidAmount.minus(appliedPayment), decimal(0));
    cursorDateKey = paymentDateKey;
  }

  const remainingDays = differenceInCalendarDays(input.calculationDateKey, cursorDateKey);
  if (remainingDays > 0 && remainingAmount.gt(0)) {
    totalFee = totalFee.plus(remainingAmount.mul(input.dailyRate).mul(remainingDays));
  }

  return money(totalFee);
}

export function installmentBalances(installment: LateFeeInstallmentInput) {
  const principalAmount = money(installment.principalAmount ?? 0);
  const interestAmount = money(installment.interestAmount ?? 0);
  const explicitTotal = installment.totalAmount === null || installment.totalAmount === undefined
    ? null
    : money(installment.totalAmount);
  const originalAmount = explicitTotal ?? money(principalAmount.plus(interestAmount));
  const paidPrincipal = money(installment.paidPrincipalAmount ?? 0);
  const paidInterest = money(installment.paidInterestAmount ?? 0);
  const componentPaidAmount = money(paidPrincipal.plus(paidInterest));
  const paidAmount = installment.paidAmount === null || installment.paidAmount === undefined
    ? componentPaidAmount
    : money(installment.paidAmount);
  return {
    originalAmount,
    paidAmount,
    outstandingAmount: maxDecimal(originalAmount.minus(paidAmount), decimal(0)),
    principalOutstanding: maxDecimal(principalAmount.minus(paidPrincipal), decimal(0)),
    interestOutstanding: maxDecimal(interestAmount.minus(paidInterest), decimal(0)),
  };
}

function paymentOutstandingAmount(payment: LateFeePaymentInput) {
  const principal = decimal(payment.principalApplied ?? 0);
  const interest = decimal(payment.interestApplied ?? 0);
  const componentAmount = principal.plus(interest);
  if (componentAmount.gt(0)) return money(componentAmount);
  return money(payment.amount ?? 0);
}

function normalizeGraceDays(value: number) {
  if (!Number.isFinite(value) || value < 0) return DEFAULT_LATE_FEE_GRACE_DAYS;
  return Math.trunc(value);
}

function addCalendarDays(dateKey: string, days: number) {
  const [year, month, day] = dateKey.split('-').map((part) => Number(part));
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return date.toISOString().slice(0, 10);
}

export { dateKeyInTimeZone, differenceInCalendarDays };

export function decimal(value: Prisma.Decimal.Value) {
  return new Prisma.Decimal(value);
}

export function money(value: Prisma.Decimal.Value) {
  return decimal(value).toDecimalPlaces(CURRENCY_SCALE, Prisma.Decimal.ROUND_HALF_UP);
}

export function formatDecimal(value: Prisma.Decimal.Value) {
  return money(value).toFixed(CURRENCY_SCALE);
}

function maxDecimal(a: Prisma.Decimal, b: Prisma.Decimal) {
  return a.gte(b) ? a : b;
}

function minDecimal(a: Prisma.Decimal, b: Prisma.Decimal) {
  return a.lte(b) ? a : b;
}
