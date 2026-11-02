import assert from "node:assert/strict";
import test from "node:test";
import {
  buildRescheduleDueDates,
  isEditableInstallment,
  isInstallmentCorrectionAction,
  validateDueDateOrdering,
} from "./installmentCorrection.service";

/** FASE 02 — reglas puras de la gestion de cuotas por el OWNER. */
test("reconoce las acciones soportadas y rechaza el resto", () => {
  for (const action of [
    "change_due_date",
    "change_amounts",
    "add_installment",
    "remove_installment",
    "reschedule",
  ]) {
    assert.equal(isInstallmentCorrectionAction(action), true, action);
  }
  assert.equal(isInstallmentCorrectionAction("delete_all"), false);
  assert.equal(isInstallmentCorrectionAction(null), false);
});

test("solo son editables las cuotas activas sin pagos aplicados", () => {
  assert.equal(isEditableInstallment({ deletedAt: null, paidAmount: 0 }), true);
  assert.equal(
    isEditableInstallment({ deletedAt: null, paidAmount: "0.00" }),
    true,
  );
  assert.equal(isEditableInstallment({ deletedAt: null, paidAmount: 500 }), false);
  assert.equal(
    isEditableInstallment({ deletedAt: new Date(), paidAmount: 0 }),
    false,
  );
});

test("valida el orden del cronograma al mover un vencimiento", () => {
  const saleDate = new Date("2026-01-01T00:00:00.000Z");
  const previous = new Date("2026-03-01T00:00:00.000Z");
  const next = new Date("2026-05-01T00:00:00.000Z");

  assert.equal(
    validateDueDateOrdering({
      dueDate: new Date("2026-04-01T00:00:00.000Z"),
      saleDate,
      previousDueDate: previous,
      nextDueDate: next,
    }),
    null,
  );
  assert.equal(
    validateDueDateOrdering({
      dueDate: new Date("2025-12-01T00:00:00.000Z"),
      saleDate,
      previousDueDate: null,
      nextDueDate: next,
    })?.code,
    "DUE_DATE_BEFORE_SALE",
  );
  assert.equal(
    validateDueDateOrdering({
      dueDate: previous,
      saleDate,
      previousDueDate: previous,
      nextDueDate: next,
    })?.code,
    "DUE_DATE_OUT_OF_ORDER",
  );
  assert.equal(
    validateDueDateOrdering({
      dueDate: next,
      saleDate,
      previousDueDate: previous,
      nextDueDate: next,
    })?.code,
    "DUE_DATE_OUT_OF_ORDER",
  );
  assert.equal(
    validateDueDateOrdering({
      dueDate: new Date("no-es-fecha"),
      saleDate,
      previousDueDate: null,
      nextDueDate: null,
    })?.code,
    "INVALID_DUE_DATE",
  );
});

test("genera vencimientos mensuales para reprogramar", () => {
  const dates = buildRescheduleDueDates(new Date("2026-02-15T00:00:00.000Z"), 3);
  assert.equal(dates.length, 3);
  assert.equal(dates[0].toISOString().slice(0, 10), "2026-02-15");
  assert.equal(dates[1].toISOString().slice(0, 10), "2026-03-15");
  assert.equal(dates[2].toISOString().slice(0, 10), "2026-04-15");
});
