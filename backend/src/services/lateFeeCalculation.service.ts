import { Prisma } from '@prisma/client';

export const PAYMENT_REMINDER_TYPE = 'OVERDUE_INSTALLMENTS';
export const DEFAULT_TIMEZONE = 'America/Santo_Domingo';

const CURRENCY_SCALE = 2;
const MAX_LATE_FEE_DAYS_PER_INSTALLMENT = 30;

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
  paidAmount?: Prisma.Decimal | number | string | null;
  status?: string | null;
  deletedAt?: Date | null;
};

export type LateFeePaymentInput = {
  installmentSyncId?: string | null;
  paidAt?: Date | null;
  amount?: Prisma.Decimal | number | string | null;
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
  diasAtraso: number;
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
      dailyRate?: Prisma.Decimal | number | string;
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
    const dailyRate = decimal(this.options.dailyRate ?? '0.01');
    const calculationDateKey = dateKeyInTimeZone(calculationDate, timezone);
    const paymentHistoryByInstallment = groupPayments(input.payments ?? []);
    const summaries = input.installments
      .filter((installment) => isCandidateInstallment(installment))
      .map((installment) => {
        const dueDate = installment.dueDate;
        if (!dueDate) return null;
        const dueDateKey = dateKeyInTimeZone(dueDate, timezone);
        const overdueDays = differenceInCalendarDays(calculationDateKey, dueDateKey);
        if (overdueDays <= 0) return null;

        const installmentAmount = money(installment.totalAmount ?? installment.principalAmount ?? 0);
        const paidAmount = money(installment.paidAmount ?? installment.paidPrincipalAmount ?? 0);
        const pendingAmount = maxDecimal(installmentAmount.minus(paidAmount), decimal(0));
        if (pendingAmount.lte(0)) return null;

        const historicalFee = calculateHistoricalLateFee({
          originalAmount: installmentAmount,
          paidAmount,
          dueDateKey,
          calculationDateKey,
          dailyRate,
          payments: paymentHistoryByInstallment.get(installment.syncId) ?? [],
          timezone,
        });
        const lateFeeDays = Math.min(overdueDays, MAX_LATE_FEE_DAYS_PER_INSTALLMENT);
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
          diasAtraso: overdueDays,
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
  payments: LateFeePaymentInput[];
  timezone: string;
}) {
  if (input.payments.length === 0 || input.paidAmount.lte(0)) return null;

  let remainingAmount = input.originalAmount;
  let unallocatedPaidAmount = input.paidAmount;
  let cursorDateKey = input.dueDateKey;
  let totalFee = decimal(0);
  let chargedDays = 0;

  for (const payment of input.payments) {
    if (!payment.paidAt || unallocatedPaidAmount.lte(0)) break;
    if (chargedDays >= MAX_LATE_FEE_DAYS_PER_INSTALLMENT) break;
    const paymentDateKey = dateKeyInTimeZone(payment.paidAt, input.timezone);
    if (paymentDateKey <= input.dueDateKey) {
      const amount = minDecimal(decimal(payment.amount ?? 0), unallocatedPaidAmount);
      remainingAmount = maxDecimal(remainingAmount.minus(amount), decimal(0));
      unallocatedPaidAmount = maxDecimal(unallocatedPaidAmount.minus(amount), decimal(0));
      continue;
    }
    if (paymentDateKey > input.calculationDateKey) continue;

    const days = differenceInCalendarDays(paymentDateKey, cursorDateKey);
    if (days > 0 && remainingAmount.gt(0)) {
      const chargeableDays = Math.min(days, MAX_LATE_FEE_DAYS_PER_INSTALLMENT - chargedDays);
      totalFee = totalFee.plus(remainingAmount.mul(input.dailyRate).mul(chargeableDays));
      chargedDays += chargeableDays;
    }

    const appliedPayment = minDecimal(decimal(payment.amount ?? 0), unallocatedPaidAmount);
    remainingAmount = maxDecimal(remainingAmount.minus(appliedPayment), decimal(0));
    unallocatedPaidAmount = maxDecimal(unallocatedPaidAmount.minus(appliedPayment), decimal(0));
    cursorDateKey = paymentDateKey;
  }

  const remainingDays = differenceInCalendarDays(input.calculationDateKey, cursorDateKey);
  if (remainingDays > 0 && remainingAmount.gt(0) && chargedDays < MAX_LATE_FEE_DAYS_PER_INSTALLMENT) {
    const chargeableDays = Math.min(remainingDays, MAX_LATE_FEE_DAYS_PER_INSTALLMENT - chargedDays);
    totalFee = totalFee.plus(remainingAmount.mul(input.dailyRate).mul(chargeableDays));
  }

  return money(totalFee);
}

export function dateKeyInTimeZone(date: Date, timezone = DEFAULT_TIMEZONE) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function differenceInCalendarDays(laterDateKey: string, earlierDateKey: string) {
  return Math.trunc((Date.parse(`${laterDateKey}T00:00:00.000Z`) - Date.parse(`${earlierDateKey}T00:00:00.000Z`)) / 86400000);
}

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
