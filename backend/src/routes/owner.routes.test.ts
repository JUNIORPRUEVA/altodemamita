import assert from 'node:assert/strict';
import test from 'node:test';
import {
  deriveSettlement,
  installmentQueueWhere,
  outstandingFromInstallments,
} from './owner.routes';

test('installmentQueueWhere normalizes camel-case dueToday state', () => {
  const today = new Date('2026-09-09T00:00:00.000Z');

  assert.deepEqual(
    installmentQueueWhere('company-1', 'dueToday', today),
    installmentQueueWhere('company-1', 'duetoday', today),
  );
});

const settledSale = {
  status: 'pagada',
  balance: '0',
  initialPendingAmount: '0',
  total: '250000',
  deletedAt: null,
};

test('clasifica como venta definitiva una venta sin saldo ni obligaciones pendientes', () => {
  const settlement = deriveSettlement({ ...settledSale }, 0);
  assert.equal(settlement.isFullyPaid, true);
  assert.equal(settlement.label, 'Saldada · Venta definitiva');
});

test('no clasifica como definitiva una venta con saldo pendiente', () => {
  assert.equal(deriveSettlement({ ...settledSale, balance: '225000' }, 0).isFullyPaid, false);
});

test('no clasifica como definitiva una venta con inicial pendiente', () => {
  assert.equal(
    deriveSettlement({ ...settledSale, initialPendingAmount: '25000' }, 0).isFullyPaid,
    false,
  );
});

test('no clasifica como definitiva una venta con cuotas cobrables pendientes', () => {
  assert.equal(deriveSettlement({ ...settledSale }, 6000).isFullyPaid, false);
  assert.equal(deriveSettlement({ ...settledSale }, 0.01).isFullyPaid, true);
  assert.equal(deriveSettlement({ ...settledSale }, 0.02).isFullyPaid, false);
});

test('una venta cancelada o eliminada nunca se clasifica como venta definitiva', () => {
  assert.equal(deriveSettlement({ ...settledSale, status: 'cancelada' }, 0).isFullyPaid, false);
  assert.equal(deriveSettlement({ ...settledSale, deletedAt: new Date() }, 0).isFullyPaid, false);
});

test('una venta sin monto contratado no se clasifica como venta definitiva', () => {
  assert.equal(deriveSettlement({ ...settledSale, total: '0' }, 0).isFullyPaid, false);
});

test('respeta la tolerancia monetaria documentada en el saldo', () => {
  assert.equal(deriveSettlement({ ...settledSale, balance: '0.01' }, 0).isFullyPaid, true);
  assert.equal(deriveSettlement({ ...settledSale, balance: '0.02' }, 0).isFullyPaid, false);
});

test('suma solo el remanente realmente pendiente de cada cuota', () => {
  assert.equal(
    outstandingFromInstallments([
      { totalAmount: '10000', paidAmount: '4000' },
      { totalAmount: '10000', paidAmount: '10000' },
    ]),
    6000,
  );
  assert.equal(outstandingFromInstallments([{ totalAmount: '10000', paidAmount: '12000' }]), 0);
  assert.equal(outstandingFromInstallments([]), 0);
});
