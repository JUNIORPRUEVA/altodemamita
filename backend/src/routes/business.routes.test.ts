import assert from 'node:assert/strict';
import test from 'node:test';
import {
  hasBlockingUserHistoryForDelete,
  isOwnerRemovalAttempt,
  isSelfDeactivation,
  normalizeBusinessUserRoleForTest,
  permissionCodesFromRowsForTest,
  permissionRowsFromCodesForTest,
  requiresUserManageForUserWriteForTest,
} from './business.routes';

test('business user role mapping accepts admin aliases as OWNER', () => {
  assert.equal(normalizeBusinessUserRoleForTest('OWNER'), 'OWNER');
  assert.equal(normalizeBusinessUserRoleForTest('admin'), 'OWNER');
  assert.equal(normalizeBusinessUserRoleForTest('SUPER_ADMIN'), 'OWNER');
  assert.equal(normalizeBusinessUserRoleForTest('TECH'), 'TECH');
});

test('business user role mapping fails closed to TECH for non-owner roles', () => {
  assert.equal(normalizeBusinessUserRoleForTest('usuario'), 'TECH');
  assert.equal(normalizeBusinessUserRoleForTest('sales_agent'), 'TECH');
  assert.equal(normalizeBusinessUserRoleForTest(undefined), undefined);
});

test('user lifecycle blocks only self deactivation attempts', () => {
  assert.equal(isSelfDeactivation('user-1', 'user-1', false), true);
  assert.equal(isSelfDeactivation('user-1', 'user-1', true), false);
  assert.equal(isSelfDeactivation('user-1', 'user-2', false), false);
});

test('user lifecycle detects active OWNER removal attempts', () => {
  assert.equal(isOwnerRemovalAttempt('OWNER', 'TECH', true), true);
  assert.equal(isOwnerRemovalAttempt('OWNER', 'OWNER', false), true);
  assert.equal(isOwnerRemovalAttempt('OWNER', 'OWNER', true), false);
  assert.equal(isOwnerRemovalAttempt('TECH', 'TECH', false), false);
});

test('user hard delete is blocked only by business history', () => {
  assert.equal(
    hasBlockingUserHistoryForDelete({
      operatedSales: 0,
      receivedPayments: 0,
      annulledPayments: 0,
    }),
    false,
  );
  assert.equal(
    hasBlockingUserHistoryForDelete({
      operatedSales: 1,
      receivedPayments: 0,
      annulledPayments: 0,
    }),
    true,
  );
  assert.equal(
    hasBlockingUserHistoryForDelete({
      operatedSales: 0,
      receivedPayments: 1,
      annulledPayments: 0,
    }),
    true,
  );
  assert.equal(
    hasBlockingUserHistoryForDelete({
      operatedSales: 0,
      receivedPayments: 0,
      annulledPayments: 1,
    }),
    true,
  );
});

test('business user permissions parse canonical codes into direct permission rows', () => {
  assert.deepEqual(
    permissionRowsFromCodesForTest([
      'payments.create',
      'clients.read',
      'payments.read',
      'sales.update',
      'lots.read',
    ]),
    [
      { module: 'clients', actions: ['read'] },
      { module: 'lots', actions: ['read'] },
      { module: 'payments', actions: ['create', 'read'] },
      { module: 'sales', actions: ['update'] },
    ],
  );
});

test('business user permissions normalize legacy aliases without broadening actions', () => {
  assert.deepEqual(
    permissionRowsFromCodesForTest([
      'pagos.anular',
      'ventas.ver',
      'solares.ver',
      'configuracion.editar',
    ]),
    [
      { module: 'configuration', actions: ['update'] },
      { module: 'lots', actions: ['read'] },
      { module: 'payments', actions: ['annul'] },
      { module: 'sales', actions: ['read'] },
    ],
  );
});

test('business user permission readback emits exact canonical codes', () => {
  assert.deepEqual(
    permissionCodesFromRowsForTest([
      { module: 'payments', actions: ['read', 'create'] },
      { module: 'sales', actions: ['read', 'update'] },
    ]),
    ['payments.create', 'payments.read', 'sales.read', 'sales.update'],
  );
});

test('business user permission writes require user management privilege', () => {
  assert.equal(requiresUserManageForUserWriteForTest({ role: 'TECH' }), false);
  assert.equal(
    requiresUserManageForUserWriteForTest({ role: 'TECH', permissions: [] }),
    true,
  );
  assert.equal(
    requiresUserManageForUserWriteForTest({ role: 'TECH', permissions: ['clients.read'] }),
    true,
  );
  assert.equal(requiresUserManageForUserWriteForTest({ role: 'OWNER' }), true);
});
