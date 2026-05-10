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
  closeTo(first.amount, 8070.240847645539, 0.000001, 'first.amount');
  closeTo(first.interestAmount, 5625, 0.01, 'first.interestAmount');
  closeTo(first.principalAmount, 2445.240847645539, 0.0001, 'first.principalAmount');
  closeTo(first.endingBalance, 560054.7591523544, 0.001, 'first.endingBalance');

  for (const installment of schedule.installments) {
    closeTo(installment.amount, first.amount, 0.000001, 'fixed payment invariant');
  }

  const last = schedule.installments[schedule.installments.length - 1];
  closeTo(last.amount, first.amount, 0.000001, 'last.amount fixed');
  closeTo(last.endingBalance, 0, 0.0001, 'last.endingBalance');
}

function runFixedPaymentCase450k() {
  const service = new LoanAccountingService();
  const schedule = service.calculateSchedule({
    principalAmount: 500000,
    downPayment: 50000,
    interestRate: 1,
    termMonths: 120,
    saleDate: new Date('2026-01-15T00:00:00.000Z'),
  });

  assert.equal(schedule.financedAmount, 450000);
  assert.equal(schedule.installments.length, 120);

  const first = schedule.installments[0];
  const second = schedule.installments[1];
  const last = schedule.installments[schedule.installments.length - 1];

  closeTo(first.amount, 6456.192678116431, 0.000001, '450k.first.amount');
  closeTo(first.interestAmount, 4500, 0.01, '450k.first.interest');
  closeTo(first.principalAmount, 1956.1926781164312, 0.0001, '450k.first.principal');
  closeTo(first.endingBalance, 448043.80732188356, 0.001, '450k.first.ending');

  closeTo(second.interestAmount, 4480.44, 0.01, '450k.second.interest');
  closeTo(second.principalAmount, 1975.7526781164314, 0.0001, '450k.second.principal');
  closeTo(second.endingBalance, 446068.0546437671, 0.001, '450k.second.ending');

  for (const installment of schedule.installments) {
    closeTo(installment.amount, first.amount, 0.000001, '450k.fixed payment invariant');
  }

  closeTo(last.amount, first.amount, 0.000001, '450k.last.amount fixed');
  closeTo(last.endingBalance, 0, 0.0001, '450k.last.ending');
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
runFixedPaymentCase450k();
runZeroRateCase();
console.log('loan-accounting-smoke-test: OK');
