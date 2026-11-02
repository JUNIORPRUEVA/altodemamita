import assert from "node:assert/strict";
import test from "node:test";
import {
  evaluatePaymentCorrection,
  type CorrectionSnapshot,
} from "./paymentCorrection";

const NOW = new Date("2026-11-02T15:00:00.000Z");
const SALE_DATE = new Date("2026-09-01T00:00:00.000Z");

function snapshot(overrides: Partial<CorrectionSnapshot> = {}): CorrectionSnapshot {
  return {
    action: "annul",
    paymentType: "cuota",
    amount: 15000,
    principalApplied: 13000,
    interestApplied: 2000,
    lateFeeApplied: 0,
    paidAt: new Date("2026-10-05T00:00:00.000Z"),
    isAnnulled: false,
    saleStatus: "activa",
    saleDate: SALE_DATE,
    hasLaterActivePayments: false,
    hasActiveInstallments: true,
    hasInstallment: true,
    installment: {
      totalAmount: 15000,
      paidAmount: 15000,
      paidPrincipalAmount: 13000,
      paidInterestAmount: 2000,
      recalculatedAfterPayment: false,
    },
    newDate: null,
    newAmount: null,
    now: NOW,
    ...overrides,
  };
}

test("rechaza el cobro de una venta al contado", () => {
  const decision = evaluatePaymentCorrection(snapshot({ paymentType: "contado" }));
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "CASH_SALE_PAYMENT_NOT_ANNULLABLE");
});

test("rechaza corregir un pago ya anulado", () => {
  const decision = evaluatePaymentCorrection(snapshot({ isAnnulled: true }));
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "PAYMENT_ALREADY_ANNULLED");
});

test("rechaza corregir pagos de una venta cancelada", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({ saleStatus: "cancelada" }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "SALE_CANCELLED");
});

test("permite anular una cuota HISTORICA con pagos posteriores", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({ hasLaterActivePayments: true }),
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.code, "OK");
  assert.equal(decision.requiresScheduleReconstruction, false);
  assert.equal(decision.createsReplacementPayment, false);
  assert.equal(decision.impact.amountRestoredToBalance, 15000);
  assert.equal(decision.impact.installment?.paidAmountAfter, 0);
  assert.equal(decision.impact.installment?.becomesOpen, true);
});

test("restaura solo las porciones aplicadas en pagos parciales", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      amount: 10000,
      principalApplied: 9000,
      interestApplied: 1000,
      installment: {
        totalAmount: 20000,
        paidAmount: 15000,
        paidPrincipalAmount: 13500,
        paidInterestAmount: 1500,
        recalculatedAfterPayment: false,
      },
    }),
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.impact.installment?.paidAmountAfter, 5000);
  assert.equal(decision.impact.installment?.paidPrincipalAfter, 4500);
  assert.equal(decision.impact.installment?.paidInterestAfter, 500);
  assert.equal(decision.impact.amountRestoredToBalance, 10000);
});

test("rechaza anular si la cuota ya no refleja las porciones del pago", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      principalApplied: 20000,
      installment: {
        totalAmount: 15000,
        paidAmount: 1000,
        paidPrincipalAmount: 1000,
        paidInterestAmount: 0,
        recalculatedAfterPayment: true,
      },
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "INSTALLMENT_ALLOCATION_INCONSISTENT");
});

test("rechaza anular un pago sin cuota asociada", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({ hasInstallment: false, installment: null }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "PAYMENT_WITHOUT_INSTALLMENT");
});

test("rechaza revertir la inicial cuando ya hay cronograma y pagos", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "abono_inicial",
      hasLaterActivePayments: true,
      hasInstallment: false,
      installment: null,
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "UPFRONT_PAYMENT_HAS_LATER_PAYMENTS");
});

test("rechaza revertir la inicial si ya se genero el cronograma", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "apartado",
      hasActiveInstallments: true,
      hasInstallment: false,
      installment: null,
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "UPFRONT_PAYMENT_SCHEDULE_ALREADY_GENERATED");
});

test("permite revertir un apartado de una venta sin cronograma", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "apartado",
      hasActiveInstallments: false,
      hasInstallment: false,
      installment: null,
      saleStatus: "apartado",
    }),
  );
  assert.equal(decision.allowed, true);
});

test("rechaza revertir un abono a capital con pagos posteriores", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "abono_capital",
      hasLaterActivePayments: true,
      hasInstallment: false,
      installment: null,
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "CAPITAL_PAYMENT_HAS_LATER_PAYMENTS");
});

test("permite revertir un abono a capital aislado exigiendo reconstruccion", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "abono_capital",
      hasInstallment: false,
      installment: null,
      principalApplied: 50000,
    }),
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.requiresScheduleReconstruction, true);
});

test("rechaza revertir una liquidacion con pagos posteriores", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      paymentType: "liquidacion_total",
      hasLaterActivePayments: true,
      hasInstallment: false,
      installment: null,
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "SETTLEMENT_PAYMENT_HAS_LATER_PAYMENTS");
});

test("cambio de fecha: permite mover la fecha efectiva", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      action: "change_date",
      newDate: new Date("2026-10-01T00:00:00.000Z"),
    }),
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.impact.dateChange, true);
  assert.ok(decision.impact.lateFeeNote);
});

test("cambio de fecha: rechaza fechas invalidas", () => {
  const beforeSale = evaluatePaymentCorrection(
    snapshot({
      action: "change_date",
      newDate: new Date("2026-08-01T00:00:00.000Z"),
    }),
  );
  assert.equal(beforeSale.code, "CORRECTION_DATE_BEFORE_SALE");

  const noDate = evaluatePaymentCorrection(
    snapshot({ action: "change_date", newDate: null }),
  );
  assert.equal(noDate.code, "CORRECTION_DATE_REQUIRED");

  const unchanged = evaluatePaymentCorrection(
    snapshot({
      action: "change_date",
      newDate: new Date("2026-10-05T00:00:00.000Z"),
    }),
  );
  assert.equal(unchanged.code, "CORRECTION_DATE_UNCHANGED");

  const future = evaluatePaymentCorrection(
    snapshot({
      action: "change_date",
      newDate: new Date("2027-01-01T00:00:00.000Z"),
    }),
  );
  assert.equal(future.code, "CORRECTION_DATE_IN_FUTURE");
});

test("cambio de fecha: bloquea mover la inicial cuando hay cronograma", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      action: "change_date",
      paymentType: "abono_inicial",
      hasInstallment: false,
      installment: null,
      newDate: new Date("2026-10-01T00:00:00.000Z"),
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "UPFRONT_DATE_LOCKED_BY_SCHEDULE");
});

test("correccion de monto: exige monto nuevo distinto", () => {
  const missing = evaluatePaymentCorrection(
    snapshot({ action: "correct_amount", newAmount: null }),
  );
  assert.equal(missing.code, "CORRECTION_AMOUNT_REQUIRED");

  const same = evaluatePaymentCorrection(
    snapshot({ action: "correct_amount", newAmount: 15000 }),
  );
  assert.equal(same.code, "CORRECTION_AMOUNT_UNCHANGED");

  const invalid = evaluatePaymentCorrection(
    snapshot({ action: "correct_amount", newAmount: -5 }),
  );
  assert.equal(invalid.code, "CORRECTION_AMOUNT_REQUIRED");
});

test("correccion de monto: solo para pagos de cuota", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      action: "correct_amount",
      paymentType: "abono_capital",
      newAmount: 9000,
      hasInstallment: false,
      installment: null,
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "CORRECTION_AMOUNT_TYPE_UNSUPPORTED");
});

test("correccion de monto: anula y crea pago de reemplazo", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({ action: "correct_amount", newAmount: 12000 }),
  );
  assert.equal(decision.allowed, true);
  assert.equal(decision.createsReplacementPayment, true);
  assert.equal(decision.impact.replacesPayment, true);
});

test("correccion de monto: hereda el rechazo de anulacion historica insegura", () => {
  const decision = evaluatePaymentCorrection(
    snapshot({
      action: "correct_amount",
      newAmount: 9000,
      principalApplied: 20000,
      installment: {
        totalAmount: 15000,
        paidAmount: 1000,
        paidPrincipalAmount: 1000,
        paidInterestAmount: 0,
        recalculatedAfterPayment: true,
      },
    }),
  );
  assert.equal(decision.allowed, false);
  assert.equal(decision.code, "INSTALLMENT_ALLOCATION_INCONSISTENT");
  assert.equal(decision.createsReplacementPayment, true);
});
