import {
  BUSINESS_TIMEZONE,
  isPastDueBusinessDay,
  resolveEffectiveInstallmentStatus,
} from './installmentStatus.service';

export type InstallmentDraft = {
  installmentNumber: number;
  dueDate: Date;
  openingBalance: number;
  principalAmount: number;
  interestAmount: number;
  totalAmount: number;
  paidAmount: number;
  paidPrincipalAmount: number;
  paidInterestAmount: number;
  endingBalance: number;
  status: string;
};

export function roundCurrency(value: number) {
  return Math.round(value * 100) / 100;
}

export function normalizeRate(ratePercent: number) {
  return ratePercent <= 0 ? 0 : ratePercent / 100;
}

export function calculateDownPaymentAmount(input: {
  salePrice: number;
  downPaymentPercentage: number;
}) {
  return roundCurrency(input.salePrice * (input.downPaymentPercentage / 100));
}

export function calculateFinancedBalance(input: {
  salePrice: number;
  downPaymentAmount: number;
}) {
  const normalizedDownPayment = Math.min(
    Math.max(input.downPaymentAmount, 0),
    input.salePrice,
  );
  return roundCurrency(input.salePrice - normalizedDownPayment);
}

export function calculatePendingInitialPayment(input: {
  requiredInitialPayment: number;
  initialPaymentPaid: number;
}) {
  const remaining = input.requiredInitialPayment - input.initialPaymentPaid;
  return remaining <= 0 ? 0 : roundCurrency(remaining);
}

export function calculateEstimatedInstallmentAmount(input: {
  financedBalance: number;
  monthlyInterest: number;
  installmentCount: number;
}) {
  const { financedBalance, monthlyInterest, installmentCount } = input;
  if (installmentCount <= 0 || financedBalance <= 0) {
    return 0;
  }

  const rateDecimal = normalizeRate(monthlyInterest);
  if (rateDecimal <= 0) {
    return financedBalance / installmentCount;
  }

  const denominator = 1 - 1 / Math.pow(1 + rateDecimal, installmentCount);
  if (Math.abs(denominator) < 0.000000000001) {
    return financedBalance / installmentCount;
  }

  return (financedBalance * rateDecimal) / denominator;
}

export function addMonths(date: Date, monthsToAdd: number) {
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

/**
 * CANONICAL CALENDAR ANCHOR — single source of truth for installment due dates.
 *
 * REGLA OFICIAL DEL PRODUCTO:
 *   dueDate(n) = saleDate + n meses calendario      (n = 1..installmentCount)
 *
 * `saleDate` es SIEMPRE el ancla. `activationDate` (fecha en que la venta quedo
 * activa / se aplico la inicial) NO mueve el calendario: puede ser igual o
 * posterior a `saleDate` sin alterar ninguna cuota.
 *
 * Semantica de mes exacta (congelada, no inventar una nueva):
 *   - se suma el mes calendario conservando la hora/minuto/segundo originales;
 *   - si el dia no existe en el mes destino se ajusta al ultimo dia del mes
 *     (2026-01-31 + 1 mes => 2026-02-28; 2028-01-31 + 1 mes => 2028-02-29;
 *      2026-03-30 + 1 mes => 2026-04-30).
 */
export function canonicalInstallmentDueDate(saleDate: Date, installmentNumber: number) {
  return addMonths(saleDate, installmentNumber);
}

export function canonicalInstallmentDueDates(saleDate: Date, installmentCount: number) {
  return Array.from({ length: Math.max(installmentCount, 0) }, (_, index) =>
    canonicalInstallmentDueDate(saleDate, index + 1),
  );
}

/**
 * Compara la dueDate recibida contra la regla canonica.
 * Devuelve `true` cuando la fecha es la esperada (comparacion al milisegundo:
 * la fecha contractual se persiste como instante, no como dia suelto).
 */
export function isCanonicalInstallmentDueDate(input: {
  saleDate: Date | null | undefined;
  installmentNumber: number | null | undefined;
  dueDate: Date | null | undefined;
}) {
  if (!input.saleDate || !input.dueDate) return false;
  if (!Number.isInteger(input.installmentNumber) || (input.installmentNumber ?? 0) <= 0) {
    return false;
  }
  const expected = canonicalInstallmentDueDate(
    input.saleDate,
    Number(input.installmentNumber),
  );
  return expected.getTime() === input.dueDate.getTime();
}

export function isPastDue(input: { dueDate: Date; asOf: Date }) {
  return isPastDueBusinessDay({
    dueDate: input.dueDate,
    businessDate: input.asOf,
    timezone: BUSINESS_TIMEZONE,
  });
}

export function resolveInstallmentStatus(input: {
  dueDate: Date;
  paidAmount: number;
  totalAmount: number;
  asOf: Date;
}) {
  if (input.paidAmount >= input.totalAmount - 0.009) {
    return 'pagada';
  }
  if (input.paidAmount > 0.009) {
    return 'parcial';
  }
  const effectiveStatus = resolveEffectiveInstallmentStatus({
    dueDate: input.dueDate,
    paidAmount: input.paidAmount,
    totalAmount: input.totalAmount,
    businessDate: input.asOf,
    timezone: BUSINESS_TIMEZONE,
  });
  return effectiveStatus === 'vencida' ? 'vencida' : 'pendiente';
}

export function buildInstallmentSchedule(input: {
  saleDate: Date;
  financedBalance: number;
  monthlyInterest: number;
  installmentCount: number;
  statusAsOf?: Date;
  startingInstallmentNumber?: number;
  dueDates?: Date[];
  fixedPaymentAmount?: number;
}) {
  const dueDates =
    input.dueDates ?? canonicalInstallmentDueDates(input.saleDate, input.installmentCount);
  if (dueDates.length <= 0 || input.financedBalance <= 0) {
    return [];
  }

  const rateDecimal = normalizeRate(input.monthlyInterest);
  const fixedPayment =
    input.fixedPaymentAmount ??
    calculateEstimatedInstallmentAmount({
      financedBalance: input.financedBalance,
      monthlyInterest: input.monthlyInterest,
      installmentCount: dueDates.length,
    });
  const statusAsOf = input.statusAsOf ?? new Date();
  const starting = input.startingInstallmentNumber ?? 1;
  let balance = input.financedBalance;
  const installments: InstallmentDraft[] = [];

  for (let index = 0; index < dueDates.length; index += 1) {
    const openingBalance = balance;
    if (openingBalance <= 0) {
      break;
    }

    const interestAmount = roundCurrency(openingBalance * rateDecimal);
    const scheduledPrincipal =
      index === dueDates.length - 1
        ? openingBalance
        : roundCurrency(fixedPayment - interestAmount);
    const principalAmount = roundCurrency(Math.min(Math.max(scheduledPrincipal, 0), openingBalance));
    const totalAmount = roundCurrency(principalAmount + interestAmount);
    const rawEndingBalance = roundCurrency(openingBalance - principalAmount);
    const endingBalance = rawEndingBalance < 0.01 ? 0 : rawEndingBalance;

    installments.push({
      installmentNumber: starting + index,
      dueDate: dueDates[index],
      openingBalance,
      principalAmount,
      interestAmount,
      totalAmount,
      paidAmount: 0,
      paidPrincipalAmount: 0,
      paidInterestAmount: 0,
      endingBalance,
      status: resolveInstallmentStatus({
        dueDate: dueDates[index],
        paidAmount: 0,
        totalAmount: fixedPayment,
        asOf: statusAsOf,
      }),
    });

    balance = endingBalance;
  }

  return installments;
}

export function resolveSaleStatus(input: {
  initialRequiredAmount: number;
  initialPaidAmount: number;
  minimumReserveAmount?: number | null;
  financedBalance: number;
}) {
  if (input.financedBalance <= 0) {
    return 'pagada';
  }
  if (input.initialPaidAmount >= input.initialRequiredAmount - 0.009) {
    return 'activa';
  }
  const reserveMinimum = input.minimumReserveAmount ?? 0;
  if (
    input.initialPaidAmount <= 0 ||
    input.initialPaidAmount < reserveMinimum - 0.009
  ) {
    return 'apartado';
  }
  return 'inicial_incompleto';
}

export function resolveUpfrontSaleStatus(input: {
  initialRequiredAmount: number;
  initialPaidAmount: number;
  financedBalance: number;
}) {
  if (input.financedBalance <= 0.009) {
    return 'pagada';
  }
  if (input.initialPaidAmount >= input.initialRequiredAmount - 0.009) {
    return 'activa';
  }
  if (input.initialPaidAmount <= 0.009) {
    return 'apartado';
  }
  return 'inicial_incompleto';
}
