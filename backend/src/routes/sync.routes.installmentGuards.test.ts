import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canonicalScheduleViolation,
  describeCanonicalDueDate,
  findLockedInstallmentFieldChanges,
  resolveIncomingInstallmentStatus,
  sameFinancialValue,
} from './sync.routes';

/**
 * FASE 4 — INVARIANTE DEL SERVIDOR.
 * Un cliente Windows/PWA antiguo o un flujo offline no puede convertir en verdad
 * oficial un calendario anomalo (el defecto del incidente P0).
 */
test('rejects a client schedule that does not follow dueDate = saleDate + n months', () => {
  const saleDate = new Date(Date.UTC(2026, 6, 15, 15, 11, 0)); // 2026-07-15
  const shifted = new Date(Date.UTC(2026, 8, 15, 15, 11, 0)); // 2026-09-15 (anomalo)
  const canonical = new Date(Date.UTC(2026, 7, 15, 15, 11, 0)); // 2026-08-15 (correcto)

  assert.equal(
    canonicalScheduleViolation({ saleDate, installmentNumber: 1, dueDate: canonical }),
    null,
  );
  assert.equal(
    canonicalScheduleViolation({ saleDate, installmentNumber: 1, dueDate: shifted }),
    'installment_due_date_not_canonical',
  );
  assert.equal(
    describeCanonicalDueDate({ saleDate, installmentNumber: 1 }),
    canonical.toISOString(),
  );
});

test('does not reject legacy payloads when there is no anchor to validate against', () => {
  const dueDate = new Date(Date.UTC(2026, 8, 15, 15, 11, 0));
  assert.equal(canonicalScheduleViolation({ saleDate: null, installmentNumber: 1, dueDate }), null);
  assert.equal(canonicalScheduleViolation({ saleDate: new Date(), installmentNumber: 0, dueDate }), null);
  assert.equal(canonicalScheduleViolation({ saleDate: new Date(), installmentNumber: 1, dueDate: null }), null);
});

/**
 * FASE 6 — PROPIEDAD DEL SERVIDOR.
 * Campos financieros y de calendario de una cuota existente no se reescriben
 * por sync generico.
 */
test('locks server-owned installment fields for existing rows', () => {
  const existing = {
    dueDate: new Date(Date.UTC(2026, 7, 15, 15, 11, 0)),
    installmentNumber: 1,
    openingBalance: '504000',
    principalAmount: '2190.94',
    interestAmount: '5040',
    totalAmount: '7230.94',
    endingBalance: '501809.06',
    saleSyncId: 'sale-d179ce4e-4e9c-4706-8941-46c1d4a17a2c',
    paidAmount: '0',
    status: 'pendiente',
  };

  // Sin cambios relevantes -> no se bloquea nada.
  assert.deepEqual(
    findLockedInstallmentFieldChanges(existing, {
      dueDate: new Date(Date.UTC(2026, 7, 15, 15, 11, 0)),
      installmentNumber: 1,
      totalAmount: '7230.94',
      paidAmount: '500',
      status: 'parcial',
      deletedAt: null,
    }),
    [],
  );

  // Intento de mover el calendario un mes (defecto P0) -> bloqueado.
  assert.deepEqual(
    findLockedInstallmentFieldChanges(existing, {
      dueDate: new Date(Date.UTC(2026, 8, 15, 15, 11, 0)),
      installmentNumber: 1,
      totalAmount: '7230.94',
    }),
    ['dueDate'],
  );

  // Intento de renumerar / cambiar importes -> bloqueado.
  assert.deepEqual(
    findLockedInstallmentFieldChanges(existing, {
      installmentNumber: 2,
      totalAmount: '8000',
    }),
    ['installmentNumber', 'totalAmount'],
  );

  // Sin fila previa no hay nada que proteger.
  assert.deepEqual(findLockedInstallmentFieldChanges(null, { dueDate: new Date() }), []);
});

test('compares money values with currency tolerance', () => {
  assert.equal(sameFinancialValue('7230.94', 7230.94), true);
  assert.equal(sameFinancialValue('7230.94', 7230.941), true);
  assert.equal(sameFinancialValue('7230.94', 7231.5), false);
  assert.equal(sameFinancialValue(null, null), true);
  assert.equal(sameFinancialValue(null, '0'), false);
});

/**
 * FASE 7 — el atraso derivado no se persiste.
 * Un cambio natural de dia no debe convertirse en una escritura de sync.
 */
test('never persists the time-derived overdue status sent by a client', () => {
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: 0,
      totalAmount: 7230.94,
    }),
    'pendiente',
  );
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: 4000,
      totalAmount: 7230.94,
    }),
    'parcial',
  );
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: 7230.94,
      totalAmount: 7230.94,
    }),
    'pagada',
  );
});

test('preserves terminal and payment-derived statuses untouched', () => {
  for (const status of ['pendiente', 'parcial', 'pagada', 'ajustada', 'cancelada', null]) {
    assert.equal(
      resolveIncomingInstallmentStatus({
        incomingStatus: status,
        paidAmount: 0,
        totalAmount: 7230.94,
      }),
      status,
    );
  }
});

test('does not fabricate a paid status when the installment has no amount', () => {
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: 0,
      totalAmount: 0,
    }),
    'vencida',
  );
});
