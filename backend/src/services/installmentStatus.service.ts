export const BUSINESS_TIMEZONE = 'America/Santo_Domingo';
export const MONEY_TOLERANCE = 0.009;

export type EffectiveInstallmentStatus =
  | 'pendiente'
  | 'vencida'
  | 'parcial'
  | 'pagada'
  | 'ajustada'
  | 'cancelada';

export type InstallmentStatusInput = {
  storedStatus?: string | null;
  dueDate?: Date | string | null;
  totalAmount?: unknown;
  paidAmount?: unknown;
  remainingAmount?: unknown;
  businessDate?: Date;
  timezone?: string;
};

export type InstallmentSummaryCounts = {
  total: number;
  paid: number;
  overdue: number;
  partial: number;
  pending: number;
};

const closedStatusMap = new Map<string, EffectiveInstallmentStatus>([
  ['pagada', 'pagada'],
  ['pagado', 'pagada'],
  ['paid', 'pagada'],
  ['ajustada', 'ajustada'],
  ['adjusted', 'ajustada'],
  ['cancelada', 'cancelada'],
  ['cancelled', 'cancelada'],
  ['canceled', 'cancelada'],
]);

export function dateKeyInTimeZone(date: Date, timezone = BUSINESS_TIMEZONE) {
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
  return Math.trunc(
    (Date.parse(`${laterDateKey}T00:00:00.000Z`) -
      Date.parse(`${earlierDateKey}T00:00:00.000Z`)) /
      86400000,
  );
}

export function resolveEffectiveInstallmentStatus(
  input: InstallmentStatusInput,
): EffectiveInstallmentStatus {
  const normalizedStored = normalizeStatus(input.storedStatus);
  const closedStatus = closedStatusMap.get(normalizedStored);
  if (closedStatus && closedStatus !== 'pagada') return closedStatus;

  const paidAmount = toNumber(input.paidAmount);
  const totalAmount = toNumber(input.totalAmount);
  const remaining =
    input.remainingAmount === undefined
      ? Math.max(totalAmount - paidAmount, 0)
      : Math.max(toNumber(input.remainingAmount), 0);

  if (closedStatus === 'pagada' || remaining <= MONEY_TOLERANCE) {
    return 'pagada';
  }

  if (
    input.dueDate &&
    isPastDueBusinessDay({
      dueDate: input.dueDate,
      businessDate: input.businessDate,
      timezone: input.timezone,
    })
  ) {
    return 'vencida';
  }

  if (paidAmount > MONEY_TOLERANCE) {
    return 'parcial';
  }

  return 'pendiente';
}

export function isPastDueBusinessDay(input: {
  dueDate: Date | string;
  businessDate?: Date;
  timezone?: string;
}) {
  const dueDate = input.dueDate instanceof Date ? input.dueDate : new Date(input.dueDate);
  if (Number.isNaN(dueDate.getTime())) return false;
  const timezone = input.timezone ?? BUSINESS_TIMEZONE;
  const dueDateKey = dateKeyInTimeZone(dueDate, timezone);
  const businessDateKey = dateKeyInTimeZone(input.businessDate ?? new Date(), timezone);
  return dueDateKey < businessDateKey;
}

export function isOpenInstallment(input: InstallmentStatusInput) {
  const status = resolveEffectiveInstallmentStatus(input);
  return status !== 'pagada' && status !== 'ajustada' && status !== 'cancelada';
}

export function isOverdueInstallment(input: InstallmentStatusInput) {
  return resolveEffectiveInstallmentStatus(input) === 'vencida';
}

/**
 * ESTADO PERSISTIDO (columna `status` de la cuota).
 *
 * Diferencia clave frente a `resolveEffectiveInstallmentStatus`:
 * el atraso NO se persiste. "Vencida" es un ESTADO EFECTIVO que se deriva en
 * lectura con `businessDate`; si se persistiera, el simple paso del dia
 * convertiria un cambio natural de fecha en una escritura de sync innecesaria
 * (y reescribiria historial financiero).
 *
 * Por eso aqui solo se persiste lo que depende de dinero o de un estado terminal:
 *   pagada  -> totalmente cubierta
 *   parcial -> hay pago, pero queda saldo
 *   pendiente -> sin pago (aunque la fecha ya haya pasado)
 *   ajustada / cancelada -> estados terminales, se preservan
 */
export function resolvePersistedInstallmentStatus(input: {
  storedStatus?: string | null;
  paidAmount?: unknown;
  totalAmount?: unknown;
  remainingAmount?: unknown;
}): EffectiveInstallmentStatus {
  const normalizedStored = normalizeStatus(input.storedStatus);
  const closedStatus = closedStatusMap.get(normalizedStored);
  if (closedStatus && closedStatus !== 'pagada') return closedStatus;

  const paidAmount = toNumber(input.paidAmount);
  const totalAmount = toNumber(input.totalAmount);
  const remaining =
    input.remainingAmount === undefined
      ? Math.max(totalAmount - paidAmount, 0)
      : Math.max(toNumber(input.remainingAmount), 0);

  if (closedStatus === 'pagada' || remaining <= MONEY_TOLERANCE) return 'pagada';
  if (paidAmount > MONEY_TOLERANCE) return 'parcial';
  return 'pendiente';
}

/**
 * Detecta estados que solo expresan paso del tiempo (`vencida` / `atrasada`).
 * Un cliente (Windows/PWA/offline) no debe poder persistir estos valores:
 * son derivados y el servidor los calcula al leer.
 */
export function isTimeDerivedOverdueStatus(status?: string | null) {
  const normalized = normalizeStatus(status);
  return normalized === 'vencida' || normalized === 'overdue' || normalized === 'atrasada';
}

export function summarizeInstallments(
  installments: InstallmentStatusInput[],
  options: { businessDate?: Date; timezone?: string } = {},
): InstallmentSummaryCounts {
  const summary: InstallmentSummaryCounts = {
    total: installments.length,
    paid: 0,
    overdue: 0,
    partial: 0,
    pending: 0,
  };

  for (const installment of installments) {
    const status = resolveEffectiveInstallmentStatus({
      ...installment,
      businessDate: options.businessDate,
      timezone: options.timezone,
    });
    if (status === 'pagada' || status === 'ajustada' || status === 'cancelada') {
      summary.paid += 1;
    } else if (status === 'vencida') {
      summary.overdue += 1;
    } else if (status === 'parcial') {
      summary.partial += 1;
    } else {
      summary.pending += 1;
    }
  }

  return summary;
}

export function normalizeStatus(status?: string | null) {
  return String(status ?? '').trim().toLowerCase();
}

export function toNumber(value: unknown) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (value === null || value === undefined) return 0;
  const parsed = Number(value.toString());
  return Number.isFinite(parsed) ? parsed : 0;
}
