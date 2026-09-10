import assert from 'node:assert/strict';
import test from 'node:test';
import { installmentQueueWhere } from './owner.routes';

test('installmentQueueWhere normalizes camel-case dueToday state', () => {
  const today = new Date('2026-09-09T00:00:00.000Z');

  assert.deepEqual(
    installmentQueueWhere('company-1', 'dueToday', today),
    installmentQueueWhere('company-1', 'duetoday', today),
  );
});
