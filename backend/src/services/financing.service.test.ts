import assert from 'node:assert/strict';
import test from 'node:test';
import {
  addMonths,
  buildInstallmentSchedule,
  calculateEstimatedInstallmentAmount,
  calculateFinancedBalance,
  calculatePendingInitialPayment,
  resolveSaleStatus,
  roundCurrency,
} from './financing.service';

test('uses local sale calculator financial formulas', () => {
  assert.equal(roundCurrency(123.456), 123.46);
  assert.equal(
    calculateFinancedBalance({ salePrice: 100000, downPaymentAmount: 20000 }),
    80000,
  );
  assert.equal(
    calculatePendingInitialPayment({
      requiredInitialPayment: 30000,
      initialPaymentPaid: 12500.123,
    }),
    17499.88,
  );

  const fixed = calculateEstimatedInstallmentAmount({
    financedBalance: 100000,
    monthlyInterest: 2,
    installmentCount: 12,
  });
  assert.equal(roundCurrency(fixed), 9455.96);
});

test('builds a French amortization schedule with local due-date behavior', () => {
  const saleDate = new Date(2026, 0, 31);
  assert.equal(addMonths(saleDate, 1).toISOString().slice(0, 10), '2026-02-28');

  const schedule = buildInstallmentSchedule({
    saleDate,
    financedBalance: 100000,
    monthlyInterest: 2,
    installmentCount: 3,
    statusAsOf: new Date(2026, 0, 31),
  });

  assert.equal(schedule.length, 3);
  assert.equal(schedule[0].installmentNumber, 1);
  assert.equal(schedule[0].dueDate.toISOString().slice(0, 10), '2026-02-28');
  assert.equal(schedule[0].interestAmount, 2000);
  assert.equal(roundCurrency(schedule[0].principalAmount), 32675.47);
  assert.equal(schedule[0].status, 'pendiente');
});

test('caps recalculated capital-payment schedule to remaining principal', () => {
  const schedule = buildInstallmentSchedule({
    saleDate: new Date(2026, 8, 9),
    financedBalance: 800,
    monthlyInterest: 1,
    installmentCount: 5,
    fixedPaymentAmount: 185.44,
    statusAsOf: new Date(2026, 8, 9),
  });

  const principalTotal = roundCurrency(
    schedule.reduce((sum, installment) => sum + installment.principalAmount, 0),
  );
  assert.equal(principalTotal, 800);
  assert.equal(schedule.at(-1)?.endingBalance, 0);
  assert.equal(schedule.at(-1)?.totalAmount, 80.32);
});

test('does not create principal in larger capital-payment recalculations', () => {
  const schedule = buildInstallmentSchedule({
    saleDate: new Date(2026, 10, 8),
    financedBalance: 88430.48,
    monthlyInterest: 1,
    installmentCount: 10,
    fixedPaymentAmount: 8529.48,
    statusAsOf: new Date(2026, 10, 8),
  });

  const principalTotal = roundCurrency(
    schedule.reduce((sum, installment) => sum + installment.principalAmount, 0),
  );
  assert.equal(principalTotal, 88430.48);
  assert.equal(schedule.at(-1)?.endingBalance, 0);
});

test('resolves sale status with apartado semantics', () => {
  assert.equal(
    resolveSaleStatus({
      initialRequiredAmount: 20000,
      initialPaidAmount: 0,
      minimumReserveAmount: 5000,
      financedBalance: 100000,
    }),
    'apartado',
  );
  assert.equal(
    resolveSaleStatus({
      initialRequiredAmount: 20000,
      initialPaidAmount: 10000,
      minimumReserveAmount: 5000,
      financedBalance: 90000,
    }),
    'inicial_incompleto',
  );
  assert.equal(
    resolveSaleStatus({
      initialRequiredAmount: 20000,
      initialPaidAmount: 20000,
      minimumReserveAmount: 5000,
      financedBalance: 80000,
    }),
    'activa',
  );
});
