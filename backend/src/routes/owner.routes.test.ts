import assert from 'node:assert/strict';
import test from 'node:test';
import {
  deriveSettlement,
  installmentQueueWhere,
  outstandingFromInstallments,
  pendingInstallmentCountFromInstallments,
  paymentSalesSearchTerms,
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

test('cuenta solo cuotas con obligacion pendiente', () => {
  const installments = [
    { status: 'pendiente', totalAmount: '1000', paidAmount: '0' },
    { status: 'parcial', totalAmount: '1000', paidAmount: '250' },
    { status: 'pagada', totalAmount: '1000', paidAmount: '1000' },
    { status: 'ajustada', totalAmount: '0', paidAmount: '0' },
    { status: 'cancelada', totalAmount: '1000', paidAmount: '0' },
    { status: 'pendiente', totalAmount: '1000', paidAmount: '1000' },
  ];

  assert.equal(pendingInstallmentCountFromInstallments(installments), 2);
});

test('la busqueda de Pagos encuentra por numero de solar visible', () => {
  const terms = paymentSalesSearchTerms('1212');
  assert.ok(terms.includes('1212'));
});

test('la busqueda de Pagos resuelve el formato de presentacion del solar', () => {
  const terms = paymentSalesSearchTerms('Mgf-S1212');
  assert.ok(terms.includes('Mgf-S1212'));
  assert.ok(terms.includes('gf'));
  assert.ok(terms.includes('1212'));
  assert.ok(terms.includes('1212'));
});

test('la busqueda de Pagos acepta cedula y telefono dominicanos', () => {
  const cedula = paymentSalesSearchTerms('756-8577557-7');
  assert.ok(cedula.includes('75685775577'));

  const phone = paymentSalesSearchTerms('(809) 555-1234');
  assert.ok(phone.includes('8095551234'));
});

test('la busqueda de Pagos no genera terminos para consultas vacias', () => {
  assert.deepEqual(paymentSalesSearchTerms('   '), []);
  assert.deepEqual(paymentSalesSearchTerms(''), []);
});
