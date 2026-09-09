import assert from 'node:assert/strict';
import test from 'node:test';
import { Prisma } from '@prisma/client';
import { applyToInstallment, resolveInstallmentsToProcess } from './authoritativePayment.service';

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
