import assert from 'node:assert/strict';
import test from 'node:test';
import {
  AdminAuthorizationError,
  __resetAdminAuthorizations,
  __setAdminAuthorizationClockForTest,
  assertAdminAuthorizationAttemptAllowed,
  clearAdminAuthorizationFailures,
  consumeAdminAuthorization,
  issueAdminAuthorization,
  registerAdminAuthorizationFailure,
} from './adminAuthorization.service';

const base = {
  companyId: 'company-1',
  action: 'payments.cancel',
  resourceType: 'PAYMENT',
  resourceId: 'payment-1',
  requestedByUserId: 'employee-1',
  authorizedByUserId: 'admin-1',
  authorizedByName: 'Administradora Uno',
};

function consume(overrides: Partial<Record<string, string>> = {}) {
  return consumeAdminAuthorization({
    id: 'missing',
    companyId: base.companyId,
    action: base.action,
    resourceType: base.resourceType,
    resourceId: base.resourceId,
    requestedByUserId: base.requestedByUserId,
    ...overrides,
  });
}

test('admin authorization is single use and keeps the authorizer identity', () => {
  __resetAdminAuthorizations();
  const record = issueAdminAuthorization(base);
  assert.equal(record.consumedAt, null);
  assert.equal(record.expiresAt > Date.now(), true);

  const consumed = consume({ id: record.id });
  assert.equal(consumed.authorizedByUserId, 'admin-1');
  assert.equal(consumed.authorizedByName, 'Administradora Uno');
  assert.notEqual(consumed.consumedAt, null);

  assert.throws(
    () => consume({ id: record.id }),
    (error: unknown) =>
      error instanceof AdminAuthorizationError &&
      error.code === 'ADMIN_AUTHORIZATION_ALREADY_USED',
  );
});

test('admin authorization cannot be reused for another payment', () => {
  __resetAdminAuthorizations();
  const record = issueAdminAuthorization(base);
  assert.throws(
    () => consume({ id: record.id, resourceId: 'payment-2' }),
    (error: unknown) =>
      error instanceof AdminAuthorizationError &&
      error.code === 'ADMIN_AUTHORIZATION_MISMATCH',
  );
  // El intento fallido no consume la autorizacion legitima.
  assert.equal(consume({ id: record.id }).authorizedByUserId, 'admin-1');
});

test('admin authorization is bound to the requesting employee and company', () => {
  __resetAdminAuthorizations();
  const record = issueAdminAuthorization(base);
  assert.throws(
    () => consume({ id: record.id, requestedByUserId: 'employee-2' }),
    (error: unknown) =>
      error instanceof AdminAuthorizationError &&
      error.code === 'ADMIN_AUTHORIZATION_MISMATCH',
  );
  assert.throws(
    () => consume({ id: record.id, companyId: 'company-2' }),
    (error: unknown) =>
      error instanceof AdminAuthorizationError &&
      error.code === 'ADMIN_AUTHORIZATION_MISMATCH',
  );
});

test('admin authorization expires and unknown ids are rejected', () => {
  __resetAdminAuthorizations();
  let current = 1_000_000;
  __setAdminAuthorizationClockForTest(() => current);
  try {
    const record = issueAdminAuthorization(base);
    current += 3 * 60 * 1000;
    assert.throws(
      () => consume({ id: record.id }),
      (error: unknown) =>
        error instanceof AdminAuthorizationError &&
        error.code === 'ADMIN_AUTHORIZATION_EXPIRED',
    );
    assert.throws(
      () => consume({ id: 'admauth_unknown' }),
      (error: unknown) =>
        error instanceof AdminAuthorizationError &&
        error.code === 'ADMIN_AUTHORIZATION_NOT_FOUND',
    );
  } finally {
    __setAdminAuthorizationClockForTest(null);
  }
});

test('repeated admin credential failures are throttled', () => {
  __resetAdminAuthorizations();
  const employee = 'employee-throttle';
  for (let attempt = 0; attempt < 4; attempt += 1) {
    registerAdminAuthorizationFailure(employee);
  }
  assert.doesNotThrow(() => assertAdminAuthorizationAttemptAllowed(employee));
  registerAdminAuthorizationFailure(employee);
  assert.throws(
    () => assertAdminAuthorizationAttemptAllowed(employee),
    (error: unknown) =>
      error instanceof AdminAuthorizationError &&
      error.code === 'ADMIN_AUTHORIZATION_THROTTLED',
  );
  clearAdminAuthorizationFailures(employee);
  assert.doesNotThrow(() => assertAdminAuthorizationAttemptAllowed(employee));
});
