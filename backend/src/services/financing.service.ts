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

export function isPastDue(input: { dueDate: Date; asOf: Date }) {
  const dueDay = new Date(
    input.dueDate.getFullYear(),
    input.dueDate.getMonth(),
    input.dueDate.getDate(),
  );
  const today = new Date(
    input.asOf.getFullYear(),
    input.asOf.getMonth(),
    input.asOf.getDate(),
  );
  return dueDay.getTime() < today.getTime();
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
  return isPastDue({ dueDate: input.dueDate, asOf: input.asOf })
    ? 'vencida'
    : 'pendiente';
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
    input.dueDates ??
    Array.from({ length: input.installmentCount }, (_, index) =>
      addMonths(input.saleDate, index + 1),
    );
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
