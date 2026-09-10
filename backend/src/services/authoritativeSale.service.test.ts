import assert from 'node:assert/strict';
import test from 'node:test';
import { Prisma } from '@prisma/client';
import {
  resolveSaleEditReferenceForTest,
  saleEditFieldClassification,
  saleHasActiveFinancialHistory,
} from './authoritativeSale.service';

test('classifies sale edit fields by financial risk', () => {
  assert.equal(saleEditFieldClassification.clientId, 'IMMUTABLE_AFTER_PAYMENT');
  assert.equal(saleEditFieldClassification.sellerId, 'IMMUTABLE_AFTER_PAYMENT');
  assert.equal(saleEditFieldClassification.lotId, 'IMMUTABLE_AFTER_PAYMENT');
  assert.equal(saleEditFieldClassification.salePrice, 'FINANCIAL_RECALCULATION_REQUIRED');
  assert.equal(saleEditFieldClassification.monthlyInterest, 'FINANCIAL_RECALCULATION_REQUIRED');
  assert.equal(saleEditFieldClassification.initialPaymentDeadline, 'SAFE_EDITABLE');
  assert.equal(saleEditFieldClassification.status, 'FORBIDDEN');
});

test('detects active financial history from payments', () => {
  assert.equal(saleHasActiveFinancialHistory({ payments: [{ id: 'payment-1' }] }), true);
});

test('detects active financial history from paid installments', () => {
  assert.equal(
    saleHasActiveFinancialHistory({
      installments: [
        {
          paidAmount: new Prisma.Decimal('0'),
          paidPrincipalAmount: new Prisma.Decimal('10'),
          paidInterestAmount: new Prisma.Decimal('0'),
        },
      ],
    }),
    true,
  );
});

test('allows sale edit audit when there are no payments or paid installments', () => {
  assert.equal(
    saleHasActiveFinancialHistory({
      payments: [],
      installments: [
        {
          paidAmount: new Prisma.Decimal('0'),
          paidPrincipalAmount: new Prisma.Decimal('0'),
          paidInterestAmount: new Prisma.Decimal('0'),
        },
      ],
    }),
    false,
  );
});

test('sale edit explicit sync reference overrides existing id reference', () => {
  assert.deepEqual(
    resolveSaleEditReferenceForTest(
      { syncId: 'requested-lot-sync' },
      { id: 'existing-lot-id', syncId: 'existing-lot-sync' },
    ),
    { id: undefined, syncId: 'requested-lot-sync' },
  );
});
