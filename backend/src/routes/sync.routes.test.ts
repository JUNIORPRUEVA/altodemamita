import assert from 'node:assert/strict';
import test from 'node:test';
import { isBlockingActiveSaleForLotDelete } from './sync.routes';

test('lot delete sync guard blocks active sale references', () => {
  assert.equal(
    isBlockingActiveSaleForLotDelete({ deletedAt: null, status: 'activa' }),
    true,
  );
  assert.equal(
    isBlockingActiveSaleForLotDelete({ deletedAt: null, status: 'inicial_incompleto' }),
    true,
  );
});

test('lot delete sync guard allows cancelled, deleted, or missing sale references', () => {
  assert.equal(
    isBlockingActiveSaleForLotDelete({ deletedAt: null, status: 'cancelada' }),
    false,
  );
  assert.equal(
    isBlockingActiveSaleForLotDelete({ deletedAt: new Date(), status: 'activa' }),
    false,
  );
  assert.equal(isBlockingActiveSaleForLotDelete(null), false);
});
