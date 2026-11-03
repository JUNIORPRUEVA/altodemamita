import assert from 'node:assert/strict';
import test from 'node:test';
import { computeCorrectionWithPayments } from './authoritativeSale.service';

test('corrección con pagos: descuenta el capital ya pagado', () => {
  const result = computeCorrectionWithPayments({
    financedBalance: 145000,
    paidPrincipalFromPayments: 33414.75,
  });
  assert.equal(result.appliedToPrincipal, 33414.75);
  assert.equal(result.outstandingBalance, 111585.25);
});

test('corrección con pagos: un segundo cambio mantiene el mismo crédito', () => {
  const first = computeCorrectionWithPayments({
    financedBalance: 145000,
    paidPrincipalFromPayments: 33414.75,
  });
  const second = computeCorrectionWithPayments({
    financedBalance: 135000,
    paidPrincipalFromPayments: 33414.75,
  });
  assert.equal(first.outstandingBalance, 111585.25);
  assert.equal(second.outstandingBalance, 101585.25);
});

test('corrección con pagos: nunca deja saldo negativo aunque hayan pagado de más', () => {
  const result = computeCorrectionWithPayments({
    financedBalance: 100000,
    paidPrincipalFromPayments: 150000,
  });
  assert.equal(result.appliedToPrincipal, 150000);
  assert.equal(result.outstandingBalance, 0);
});

test('corrección con pagos: toma el mayor entre pagos y cuotas pagadas', () => {
  const result = computeCorrectionWithPayments({
    financedBalance: 450000,
    paidPrincipalFromPayments: 0,
    paidPrincipalFromInstallments: 30000,
  });
  assert.equal(result.appliedToPrincipal, 30000);
  assert.equal(result.outstandingBalance, 420000);
});

test('corrección con pagos: no suma dos veces el mismo dinero', () => {
  const result = computeCorrectionWithPayments({
    financedBalance: 450000,
    paidPrincipalFromPayments: 32000,
    paidPrincipalFromInstallments: 32000,
  });
  assert.equal(result.appliedToPrincipal, 32000);
  assert.equal(result.outstandingBalance, 418000);
});

test('corrección sin pagos conserva la agenda completa', () => {
  const result = computeCorrectionWithPayments({
    financedBalance: 450000,
  });
  assert.equal(result.appliedToPrincipal, 0);
  assert.equal(result.outstandingBalance, 450000);
});
