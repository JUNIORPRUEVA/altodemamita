import { strict as assert } from 'node:assert';

import { LoanAccountingService } from '../src/shared/services/loan-accounting.service';

function closeTo(actual: number, expected: number, tolerance: number, label: string) {
  const diff = Math.abs(actual - expected);
  assert(
    diff <= tolerance,
    `${label}: expected ${expected}, got ${actual}, diff ${diff} > tolerance ${tolerance}`,
  );
}

function runExcelCase() {
  const service = new LoanAccountingService();
  const schedule = service.calculateSchedule({
    principalAmount: 625000,
    downPayment: 62500,
    interestRate: 1,
    termMonths: 120,
    saleDate: new Date('2026-01-15T00:00:00.000Z'),
  });

  assert.equal(schedule.financedAmount, 562500);
  assert.equal(schedule.installments.length, 120);

  const first = schedule.installments[0];
  closeTo(first.amount, 8070.24, 0.01, 'first.amount');
  closeTo(first.interestAmount, 5625, 0.01, 'first.interestAmount');
  closeTo(first.principalAmount, 2445.24, 0.01, 'first.principalAmount');
  closeTo(first.endingBalance, 560054.76, 0.01, 'first.endingBalance');

  const last = schedule.installments[schedule.installments.length - 1];
  closeTo(last.endingBalance, 0, 0.0001, 'last.endingBalance');

  const totalPrincipal = schedule.installments.reduce(
    (sum, installment) => sum + installment.principalAmount,
    0,
  );
  closeTo(totalPrincipal, 562500, 0.01, 'totalPrincipal');
}

function runZeroRateCase() {
  const service = new LoanAccountingService();
  const schedule = service.calculateSchedule({
    principalAmount: 120000,
    downPayment: 0,
    interestRate: 0,
    termMonths: 12,
    saleDate: new Date('2026-01-15T00:00:00.000Z'),
  });

  assert.equal(schedule.installments.length, 12);
  closeTo(schedule.installments[0].amount, 10000, 0.01, 'zero-rate amount');
  closeTo(schedule.installments[0].interestAmount, 0, 0.0001, 'zero-rate first interest');
  closeTo(
    schedule.installments[schedule.installments.length - 1].endingBalance,
    0,
    0.0001,
    'zero-rate last ending balance',
  );
}

runExcelCase();
runZeroRateCase();
console.log('loan-accounting-smoke-test: OK');
