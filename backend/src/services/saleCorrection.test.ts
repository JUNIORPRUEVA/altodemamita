import assert from "node:assert/strict";
import test from "node:test";
import {
  isSaleCorrectionAction,
  saleStatusFor,
  validateFinancing,
} from "./saleCorrection.service";

/** FASE 03 — reglas puras de la administracion de ventas. */
test("reconoce las acciones de venta soportadas", () => {
  for (const action of [
    "update_financing",
    "change_client",
    "change_lot",
    "cancel",
    "restore",
  ]) {
    assert.equal(isSaleCorrectionAction(action), true, action);
  }
  assert.equal(isSaleCorrectionAction("delete_everything"), false);
  assert.equal(isSaleCorrectionAction(undefined), false);
});

test("valida el financiamiento del contrato", () => {
  assert.equal(
    validateFinancing({
      totalPrice: 50000,
      initialPaidAmount: 10000,
      initialRequiredAmount: 10000,
      installmentCount: 4,
      monthlyInterestRate: 2,
    }),
    null,
  );
  assert.equal(
    validateFinancing({
      totalPrice: 0,
      initialPaidAmount: 0,
      initialRequiredAmount: 0,
      installmentCount: 1,
      monthlyInterestRate: 0,
    })?.code,
    "INVALID_SALE_PRICE",
  );
  assert.equal(
    validateFinancing({
      totalPrice: 1000,
      initialPaidAmount: 2000,
      initialRequiredAmount: 0,
      installmentCount: 1,
      monthlyInterestRate: 0,
    })?.code,
    "INVALID_INITIAL_PAID",
  );
  assert.equal(
    validateFinancing({
      totalPrice: 1000,
      initialPaidAmount: 100,
      initialRequiredAmount: 100,
      installmentCount: 500,
      monthlyInterestRate: 0,
    })?.code,
    "INVALID_INSTALLMENT_COUNT",
  );
  assert.equal(
    validateFinancing({
      totalPrice: 1000,
      initialPaidAmount: 100,
      initialRequiredAmount: 100,
      installmentCount: 2,
      monthlyInterestRate: 150,
    })?.code,
    "INVALID_INTEREST_RATE",
  );
  assert.equal(
    validateFinancing({
      totalPrice: 1000,
      initialPaidAmount: 100,
      initialRequiredAmount: 100,
      installmentCount: 0,
      monthlyInterestRate: 0,
    })?.code,
    "INSTALLMENTS_REQUIRED",
  );
});

test("deriva el estado de la venta desde sus saldos", () => {
  // Inicial incompleta -> apartado/inicial_incompleto (nunca "activa").
  const upfront = saleStatusFor({
    initialRequiredAmount: 20000,
    initialPaidAmount: 5000,
    financedBalance: 0,
  });
  assert.notEqual(upfront, "activa");
  // Inicial completa y saldo financiado -> activa.
  const active = saleStatusFor({
    initialRequiredAmount: 10000,
    initialPaidAmount: 10000,
    financedBalance: 40000,
  });
  assert.equal(active, "activa");
  // Sin saldo pendiente -> pagada.
  const paid = saleStatusFor({
    initialRequiredAmount: 10000,
    initialPaidAmount: 10000,
    financedBalance: 0,
  });
  assert.equal(paid, "pagada");
});
