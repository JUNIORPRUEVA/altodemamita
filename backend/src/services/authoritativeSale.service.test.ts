import assert from 'node:assert/strict';
import test from 'node:test';
import { shouldBlockSaleDateEditWithExistingInstallments } from './authoritativeSale.service';

test('blocks normal saleDate edits when financed installments already exist', () => {
  assert.equal(
    shouldBlockSaleDateEditWithExistingInstallments({
      requestedSaleDate: '2026-07-15T15:11:00.000Z',
      existingSaleDate: new Date('2026-08-15T15:11:00.000Z'),
      activeInstallmentCount: 120,
    }),
    true,
  );
});

test('does not block unchanged saleDate or sales without generated installments', () => {
  assert.equal(
    shouldBlockSaleDateEditWithExistingInstallments({
      requestedSaleDate: '2026-08-15T15:11:00.000Z',
      existingSaleDate: new Date('2026-08-15T15:11:00.000Z'),
      activeInstallmentCount: 120,
    }),
    false,
  );
  assert.equal(
    shouldBlockSaleDateEditWithExistingInstallments({
      requestedSaleDate: '2026-07-15T15:11:00.000Z',
      existingSaleDate: new Date('2026-08-15T15:11:00.000Z'),
      activeInstallmentCount: 0,
    }),
    false,
  );
});
