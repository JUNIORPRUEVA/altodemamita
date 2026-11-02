import { roundCurrency } from "./financing.service";

/**
 * FASE 01C — Motor de correccion de pagos historicos (decision pura).
 *
 * Este modulo NO toca la base de datos: recibe el estado ya cargado de un pago
 * y decide si la correccion es financieramente segura, devolviendo el impacto
 * previsto. La orquestacion transaccional vive en
 * `authoritativePayment.service.ts` (`previewPaymentCorrection` /
 * `applyPaymentCorrection`).
 *
 * Principio rector: si la reconstruccion determinista no puede demostrarse, la
 * correccion se RECHAZA con una instruccion accionable en lugar de aceptar una
 * escritura que rompa invariantes.
 */

export type CorrectionAction = "annul" | "change_date" | "correct_amount";

export const CORRECTION_ACTIONS: readonly CorrectionAction[] = [
  "annul",
  "change_date",
  "correct_amount",
];

export function isCorrectionAction(value: unknown): value is CorrectionAction {
  return (
    typeof value === "string" &&
    (CORRECTION_ACTIONS as readonly string[]).includes(value)
  );
}

/** Tipos que NO admiten anulacion individual (cobro de venta al contado). */
const CASH_SALE_TYPES = new Set(["contado"]);

/**
 * Tipos "upfront": mueven la inicial/reserva y, al activarse la venta, generan
 * el cronograma completo. Revertirlos cuando ya existe cronograma o pagos
 * posteriores destruiria la evidencia del calendario, asi que se rechaza.
 */
const UPFRONT_TYPES = new Set(["apartado", "abono_inicial", "inicial"]);

/** Abono a capital: regenera el calendario de cuotas restantes. */
const CAPITAL_TYPES = new Set(["abono_capital"]);

/** Liquidacion total: revierte a un snapshot previo de la venta. */
const SETTLEMENT_TYPES = new Set(["liquidacion_total"]);

export type CorrectionSnapshot = {
  action: CorrectionAction;
  paymentType: string | null;
  amount: number;
  principalApplied: number;
  interestApplied: number;
  lateFeeApplied: number;
  /** Fecha efectiva actual del pago (`paidAt`). */
  paidAt: Date;
  /** `true` si el pago ya fue anulado o borrado logicamente. */
  isAnnulled: boolean;
  saleStatus: string | null;
  saleDate: Date | null;
  /** Existen pagos activos POSTERIORES a este en la misma venta. */
  hasLaterActivePayments: boolean;
  /** La venta ya tiene cronograma de cuotas activo. */
  hasActiveInstallments: boolean;
  /** El pago afecta a una cuota concreta. */
  hasInstallment: boolean;
  /** Saldos actuales de la cuota afectada (si existe). */
  installment: {
    totalAmount: number;
    paidAmount: number;
    paidPrincipalAmount: number;
    paidInterestAmount: number;
    /** `true` si esta cuota fue recalculada despues del pago (version > 1). */
    recalculatedAfterPayment: boolean;
  } | null;
  /** Parametros de la accion. */
  newDate?: Date | null;
  newAmount?: number | null;
  /** Reloj de referencia (inyectable en pruebas). */
  now: Date;
};

export type CorrectionImpact = {
  amountRestoredToBalance: number;
  installment:
    | {
        paidAmountBefore: number;
        paidAmountAfter: number;
        paidPrincipalAfter: number;
        paidInterestAfter: number;
        statusBefore: string | null;
        becomesOpen: boolean;
      }
    | null;
  saleBalanceBefore: number;
  saleBalanceAfter: number;
  dateChange: boolean;
  replacesPayment: boolean;
  lateFeeNote: string | null;
};

export type CorrectionDecision = {
  allowed: boolean;
  code: string;
  message: string;
  /** La operacion exige regenerar el cronograma (abono a capital). */
  requiresScheduleReconstruction: boolean;
  /** Se conserva el evento original y se registra uno nuevo de reemplazo. */
  createsReplacementPayment: boolean;
  impact: CorrectionImpact;
};

export type CorrectionSnapshotInput = Omit<CorrectionSnapshot, "now"> & {
  now?: Date;
};

function reject(
  code: string,
  message: string,
  impact: CorrectionImpact,
  extra: Partial<Pick<CorrectionDecision, "requiresScheduleReconstruction" | "createsReplacementPayment">> = {},
): CorrectionDecision {
  return {
    allowed: false,
    code,
    message,
    requiresScheduleReconstruction: extra.requiresScheduleReconstruction ?? false,
    createsReplacementPayment: extra.createsReplacementPayment ?? false,
    impact,
  };
}

function buildImpact(snapshot: CorrectionSnapshot): CorrectionImpact {
  const installment = snapshot.installment;
  const installmentImpact = installment
    ? (() => {
        const principalAfter = roundCurrency(
          Math.max(
            installment.paidPrincipalAmount - snapshot.principalApplied,
            0,
          ),
        );
        const interestAfter = roundCurrency(
          Math.max(
            installment.paidInterestAmount - snapshot.interestApplied,
            0,
          ),
        );
        const paidAfter = roundCurrency(principalAfter + interestAfter);
        return {
          paidAmountBefore: installment.paidAmount,
          paidAmountAfter: paidAfter,
          paidPrincipalAfter: principalAfter,
          paidInterestAfter: interestAfter,
          statusBefore: null as string | null,
          becomesOpen: paidAfter < installment.totalAmount - 0.009,
        };
      })()
    : null;

  const restored = roundCurrency(
    snapshot.principalApplied + snapshot.interestApplied,
  );
  return {
    amountRestoredToBalance: restored,
    installment: installmentImpact,
    saleBalanceBefore: 0,
    saleBalanceAfter: 0,
    dateChange: snapshot.action === "change_date",
    replacesPayment: snapshot.action === "correct_amount",
    lateFeeNote: null,
  };
}

function validateCommon(snapshot: CorrectionSnapshot): CorrectionDecision | null {
  if (snapshot.isAnnulled) {
    return reject(
      "PAYMENT_ALREADY_ANNULLED",
      "Este pago ya fue anulado: no se puede corregir ni anular dos veces.",
      buildImpact(snapshot),
    );
  }
  if (snapshot.amount <= 0) {
    return reject(
      "INVALID_PAYMENT_AMOUNT",
      "El pago no tiene un monto valido.",
      buildImpact(snapshot),
    );
  }
  if (snapshot.saleStatus === "cancelada") {
    return reject(
      "SALE_CANCELLED",
      "La venta esta cancelada: no se corrigen pagos de una venta cancelada.",
      buildImpact(snapshot),
    );
  }
  return null;
}

function validateAnnul(snapshot: CorrectionSnapshot): CorrectionDecision | null {
  const type = (snapshot.paymentType ?? "").trim().toLowerCase();
  const impact = buildImpact(snapshot);

  if (CASH_SALE_TYPES.has(type)) {
    return reject(
      "CASH_SALE_PAYMENT_NOT_ANNULLABLE",
      "El cobro de una venta al contado no se puede anular individualmente: anula o revierte la venta completa desde Ventas.",
      impact,
    );
  }

  if (UPFRONT_TYPES.has(type)) {
    if (snapshot.hasLaterActivePayments) {
      return reject(
        "UPFRONT_PAYMENT_HAS_LATER_PAYMENTS",
        "El pago de inicial/reserva ya genero el cronograma y tiene pagos posteriores: anula primero los pagos posteriores (de la ultima cuota hacia atras).",
        impact,
      );
    }
    if (snapshot.hasActiveInstallments) {
      return reject(
        "UPFRONT_PAYMENT_SCHEDULE_ALREADY_GENERATED",
        "El pago de inicial/reserva ya activo la venta y genero cuotas: revertirlo borraria el cronograma. Corrige su fecha o anula la venta completa desde Ventas.",
        impact,
      );
    }
    return {
      allowed: true,
      code: "OK",
      message: "Reversion de pago de inicial/reserva segura: la venta vuelve al estado previo.",
      requiresScheduleReconstruction: false,
      createsReplacementPayment: false,
      impact,
    };
  }

  if (CAPITAL_TYPES.has(type)) {
    if (snapshot.hasLaterActivePayments) {
      return reject(
        "CAPITAL_PAYMENT_HAS_LATER_PAYMENTS",
        "El abono a capital regenero el calendario y tiene pagos posteriores: anula primero los pagos posteriores.",
        impact,
      );
    }
    return {
      allowed: true,
      code: "OK",
      message: "Reversion de abono a capital: se reconstruye el calendario desde el saldo restaurado.",
      requiresScheduleReconstruction: true,
      createsReplacementPayment: false,
      impact,
    };
  }

  if (SETTLEMENT_TYPES.has(type)) {
    if (snapshot.hasLaterActivePayments) {
      return reject(
        "SETTLEMENT_PAYMENT_HAS_LATER_PAYMENTS",
        "La liquidacion total tiene pagos posteriores: anula primero los pagos posteriores.",
        impact,
      );
    }
    return {
      allowed: true,
      code: "OK",
      message: "Reversion de liquidacion total: se restaura el estado previo a la liquidacion.",
      requiresScheduleReconstruction: false,
      createsReplacementPayment: false,
      impact,
    };
  }

  // Pago de cuota (o tipo legacy equivalente).
  if (!snapshot.hasInstallment) {
    return reject(
      "PAYMENT_WITHOUT_INSTALLMENT",
      "El pago no esta asociado a una cuota: no se puede reconstruir su efecto.",
      impact,
    );
  }
  const installment = snapshot.installment;
  if (!installment) {
    return reject(
      "INSTALLMENT_NOT_FOUND",
      "La cuota afectada por el pago ya no existe en la venta.",
      impact,
    );
  }
  if (
    snapshot.principalApplied > installment.paidPrincipalAmount + 0.009 ||
    snapshot.interestApplied > installment.paidInterestAmount + 0.009
  ) {
    return reject(
      "INSTALLMENT_ALLOCATION_INCONSISTENT",
      "La cuota ya no refleja las porciones aplicadas por este pago: la anulacion dejaria montos negativos. Revisa el historial de la venta.",
      impact,
    );
  }
  return {
    allowed: true,
    code: "OK",
    message: snapshot.hasLaterActivePayments
      ? "Reversion historica segura: se descuentan las porciones aplicadas de este pago y se recalculan estado y saldo de la venta. Los pagos posteriores conservan sus montos."
      : "Reversion segura: se descuentan las porciones aplicadas y se recalculan estado y saldo.",
    requiresScheduleReconstruction: false,
    createsReplacementPayment: false,
    impact,
  };
}

function validateChangeDate(snapshot: CorrectionSnapshot): CorrectionDecision | null {
  const impact = buildImpact(snapshot);
  const newDate = snapshot.newDate;
  if (!newDate || Number.isNaN(newDate.getTime())) {
    return reject(
      "CORRECTION_DATE_REQUIRED",
      "Indica la nueva fecha efectiva del pago.",
      impact,
    );
  }
  if (snapshot.saleDate && newDate.getTime() < snapshot.saleDate.getTime()) {
    return reject(
      "CORRECTION_DATE_BEFORE_SALE",
      "La fecha efectiva del pago no puede ser anterior a la fecha de la venta.",
      impact,
    );
  }
  const tomorrow = new Date(snapshot.now.getTime() + 24 * 60 * 60 * 1000);
  if (newDate.getTime() > tomorrow.getTime()) {
    return reject(
      "CORRECTION_DATE_IN_FUTURE",
      "La fecha efectiva del pago no puede estar en el futuro.",
      impact,
    );
  }
  if (newDate.getTime() === snapshot.paidAt.getTime()) {
    return reject(
      "CORRECTION_DATE_UNCHANGED",
      "La fecha indicada es la misma que ya tiene el pago.",
      impact,
    );
  }
  const type = (snapshot.paymentType ?? "").trim().toLowerCase();
  if (UPFRONT_TYPES.has(type) && snapshot.hasActiveInstallments) {
    return reject(
      "UPFRONT_DATE_LOCKED_BY_SCHEDULE",
      "La fecha del pago de inicial/reserva ancla la activacion y el cronograma: no se puede mover sin recalcular el contrato.",
      impact,
    );
  }
  return {
    allowed: true,
    code: "OK",
    message:
      "Se cambia solo la FECHA EFECTIVA del pago. La fecha de creacion original se conserva como evidencia y el estado de la cuota se recalcula (vencida/pendiente).",
    requiresScheduleReconstruction: false,
    createsReplacementPayment: false,
    impact: {
      ...impact,
      dateChange: true,
      lateFeeNote:
        "La mora exigible se recalcula con la nueva fecha: si el pago se registra ANTES, la mora acumulada pendiente baja; si se registra DESPUES, sube. La mora ya cobrada en este pago no se modifica.",
    },
  };
}

function validateCorrectAmount(snapshot: CorrectionSnapshot): CorrectionDecision | null {
  const impact = buildImpact(snapshot);
  const newAmount = snapshot.newAmount;
  if (newAmount == null || Number.isNaN(newAmount) || newAmount <= 0) {
    return reject(
      "CORRECTION_AMOUNT_REQUIRED",
      "Indica el monto correcto (mayor que cero).",
      impact,
    );
  }
  const rounded = roundCurrency(newAmount);
  if (Math.abs(rounded - roundCurrency(snapshot.amount)) < 0.005) {
    return reject(
      "CORRECTION_AMOUNT_UNCHANGED",
      "El monto indicado es igual al actual.",
      impact,
    );
  }
  const type = (snapshot.paymentType ?? "").trim().toLowerCase();
  if (!["cuota", "cuota_vencida", "todas_cuotas_vencidas", "cuotas_adelantadas", ""].includes(type)) {
    return reject(
      "CORRECTION_AMOUNT_TYPE_UNSUPPORTED",
      "Solo se corrige el monto de pagos de cuota. Para inicial, capital o liquidacion usa anulacion + registro nuevo.",
      impact,
    );
  }
  const annulDecision = validateAnnul(snapshot);
  if (annulDecision && !annulDecision.allowed) {
    return reject(
      annulDecision.code,
      annulDecision.message,
      impact,
      { createsReplacementPayment: true },
    );
  }
  return {
    allowed: true,
    code: "OK",
    message:
      "Se ANULA el pago original (conservando su evidencia) y se registra un pago de REEMPLAZO con el monto corregido, aplicado por el motor financiero del backend.",
    requiresScheduleReconstruction: false,
    createsReplacementPayment: true,
    impact: {
      ...impact,
      replacesPayment: true,
      amountRestoredToBalance: roundCurrency(
        snapshot.principalApplied + snapshot.interestApplied,
      ),
    },
  };
}

/**
 * Decide si la correccion solicitada es financieramente segura.
 */
export function evaluatePaymentCorrection(
  input: CorrectionSnapshotInput,
): CorrectionDecision {
  const snapshot: CorrectionSnapshot = {
    ...input,
    now: input.now ?? new Date(),
  };

  const common = validateCommon(snapshot);
  if (common) return common;

  switch (snapshot.action) {
    case "annul":
      return validateAnnul(snapshot)!;
    case "change_date":
      return validateChangeDate(snapshot) ?? {
        allowed: true,
        code: "OK",
        message: "Cambio de fecha permitido.",
        requiresScheduleReconstruction: false,
        createsReplacementPayment: false,
        impact: buildImpact(snapshot),
      };
    case "correct_amount":
      return validateCorrectAmount(snapshot)!;
    default:
      return reject(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion no soportada.",
        buildImpact(snapshot),
      );
  }
}
