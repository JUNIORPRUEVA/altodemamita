import assert from 'node:assert/strict';
import test from 'node:test';
import { Prisma } from '@prisma/client';
import {
  applyToInstallment,
  buildSettlementQuoteForTest,
  resolveInstallmentsToProcess,
} from './authoritativePayment.service';

const installment = {
  id: 'inst-1',
  companyId: 'company-1',
  syncId: 'installment-sync-1',
  saleId: 'sale-1',
  saleSyncId: 'sale-sync-1',
  installmentNumber: 1,
  dueDate: new Date(2026, 0, 1),
  openingBalance: new Prisma.Decimal(100000),
  principalAmount: new Prisma.Decimal(8000),
  interestAmount: new Prisma.Decimal(2000),
  totalAmount: new Prisma.Decimal(10000),
  paidAmount: new Prisma.Decimal(0),
  paidPrincipalAmount: new Prisma.Decimal(0),
  paidInterestAmount: new Prisma.Decimal(0),
  status: 'vencida',
  raw: null,
  version: 1,
  deletedAt: null,
  createdAt: new Date(),
  updatedAt: new Date(),
  endingBalance: new Prisma.Decimal(92000),
};

test('applies installment payment interest first then principal', () => {
  const outcome = applyToInstallment(installment, 2500, new Date(2026, 0, 2));

  assert.equal(outcome.appliedAmount, 2500);
  assert.equal(outcome.interestPaidNow, 2000);
  assert.equal(outcome.principalPaidNow, 500);
  assert.equal(outcome.newInterestPaid, 2000);
  assert.equal(outcome.newPrincipalPaid, 500);
  assert.equal(outcome.newStatus, 'parcial');
});

test('applies installment payment to late fee before interest and principal', () => {
  const outcome = applyToInstallment(installment, 2500, new Date(2026, 0, 8), 600);

  assert.equal(outcome.appliedAmount, 2500);
  assert.equal(outcome.lateFeePaidNow, 600);
  assert.equal(outcome.interestPaidNow, 1900);
  assert.equal(outcome.principalPaidNow, 0);
  assert.equal(outcome.newPaidAmount, 1900);
  assert.equal(outcome.remainingAmount, 0);
  assert.equal(outcome.newStatus, 'parcial');
});

test('selects all overdue installments for overdue batch mode', () => {
  const future = {
    ...installment,
    id: 'inst-2',
    installmentNumber: 2,
    dueDate: new Date(2026, 2, 1),
    status: 'pendiente',
  };

  const selected = resolveInstallmentsToProcess({
    installments: [installment, future],
    paymentDate: new Date(2026, 1, 1),
    paymentTypeOverride: 'todas_cuotas_vencidas',
  });

  assert.deepEqual(
    selected.map((item) => item.id),
    ['inst-1'],
  );
});

test('selects installments due today by business date, not by exact hour', () => {
  const dueLaterToday = {
    ...installment,
    id: 'inst-due-today',
    installmentNumber: 2,
    dueDate: new Date('2026-09-15T23:30:00.000-04:00'),
    status: 'pendiente',
  };
  const future = {
    ...installment,
    id: 'inst-future',
    installmentNumber: 3,
    dueDate: new Date('2026-09-16T00:00:00.000-04:00'),
    status: 'pendiente',
  };

  const selected = resolveInstallmentsToProcess({
    installments: [dueLaterToday, future],
    paymentDate: new Date('2026-09-15T08:00:00.000-04:00'),
    paymentTypeOverride: 'cuota',
  });

  assert.deepEqual(
    selected.map((item) => item.id),
    ['inst-due-today'],
  );
});

test('settlement quote treats due-today interest as due for the whole business day', () => {
  const dueLaterToday = {
    ...installment,
    id: 'inst-due-today',
    installmentNumber: 2,
    dueDate: new Date('2026-09-15T23:30:00.000-04:00'),
    interestAmount: new Prisma.Decimal(1500),
    totalAmount: new Prisma.Decimal(9500),
    status: 'pendiente',
  };
  const future = {
    ...installment,
    id: 'inst-future',
    installmentNumber: 3,
    dueDate: new Date('2026-09-16T00:00:00.000-04:00'),
    interestAmount: new Prisma.Decimal(500),
    totalAmount: new Prisma.Decimal(8500),
    status: 'pendiente',
  };

  const quote = buildSettlementQuoteForTest({
    sale: {
      id: 'sale-1',
      version: 4,
      balance: new Prisma.Decimal(24000),
      initialPendingAmount: new Prisma.Decimal(0),
      status: 'activa',
    } as never,
    installments: [dueLaterToday, future] as never,
    asOfDate: new Date('2026-09-15T08:00:00.000-04:00'),
  });

  assert.equal(quote.dueInterest, 1500);
  assert.equal(quote.futureInterestWaived, 500);
});

test('settlement quote charges outstanding principal and due interest only', () => {
  const future = {
    ...installment,
    id: 'inst-2',
    installmentNumber: 2,
    dueDate: new Date(2026, 2, 1),
    openingBalance: new Prisma.Decimal(92000),
    principalAmount: new Prisma.Decimal(9000),
    interestAmount: new Prisma.Decimal(1000),
    totalAmount: new Prisma.Decimal(10000),
    paidAmount: new Prisma.Decimal(0),
    paidPrincipalAmount: new Prisma.Decimal(0),
    paidInterestAmount: new Prisma.Decimal(0),
    endingBalance: new Prisma.Decimal(83000),
    status: 'pendiente',
  };
  const partialOverdue = {
    ...installment,
    id: 'inst-3',
    installmentNumber: 3,
    principalAmount: new Prisma.Decimal(7000),
    interestAmount: new Prisma.Decimal(3000),
    totalAmount: new Prisma.Decimal(10000),
    paidAmount: new Prisma.Decimal(2500),
    paidPrincipalAmount: new Prisma.Decimal(0),
    paidInterestAmount: new Prisma.Decimal(2500),
    status: 'parcial',
  };

  const quote = buildSettlementQuoteForTest({
    sale: {
      id: 'sale-1',
      version: 4,
      balance: new Prisma.Decimal(24000),
      initialPendingAmount: new Prisma.Decimal(0),
      status: 'activa',
    } as never,
    installments: [installment, future, partialOverdue] as never,
    asOfDate: new Date(2026, 1, 1),
  });

  assert.equal(quote.principalOutstanding, 24000);
  assert.equal(quote.dueInterest, 2500);
  assert.equal(quote.futureInterestWaived, 1000);
  assert.equal(quote.lateFees, 0);
  assert.equal(quote.settlementAmount, 26500);
  assert.equal(typeof quote.quoteVersion, 'string');
  assert.ok(quote.quoteVersion.length > 10);
});

test('settlement quote fingerprint changes when financial state changes', () => {
  const baseSale = {
    id: 'sale-1',
    version: 4,
    balance: new Prisma.Decimal(8000),
    initialPendingAmount: new Prisma.Decimal(0),
    status: 'activa',
  };
  const first = buildSettlementQuoteForTest({
    sale: baseSale as never,
    installments: [installment] as never,
    asOfDate: new Date(2026, 1, 1),
  });
  const second = buildSettlementQuoteForTest({
    sale: { ...baseSale, version: 5 } as never,
    installments: [installment] as never,
    asOfDate: new Date(2026, 1, 1),
  });

  assert.notEqual(first.quoteVersion, second.quoteVersion);
});
