import assert from 'node:assert/strict';
import test from 'node:test';
import { buildAuthContractUser } from './authContract';

test('valid production-style OWNER user auth payload includes Windows minimum fields', () => {
  const user = buildAuthContractUser({
    id: 'user-prod-1',
    email: 'admin@sistema.local',
    name: 'Administracion',
    role: 'OWNER',
  });

  assert.equal(user.sub, 'user-prod-1');
  assert.equal(user.email, 'admin@sistema.local');
  assert.equal(user.fullName, 'Administracion');
  assert.equal(user.username, 'admin');
  assert.equal(user.isActive, true);
  assert.deepEqual(user.roles, ['SUPER_ADMIN']);
  assert.ok(user.permissions.includes('users.read'));
  assert.ok(user.permissions.includes('sales.write'));
});

test('remote user minimum-data validation would pass with contract payload', () => {
  const user = buildAuthContractUser({
    id: 'user-prod-1',
    email: 'admin@sistema.local',
    name: 'Administracion',
    role: 'OWNER',
  });

  assert.equal(typeof user.sub, 'string');
  assert.notEqual(user.sub.trim(), '');
  assert.equal(typeof user.email, 'string');
  assert.notEqual(user.email.trim(), '');
});

test('missing truly-required source field still fails safely in assertions', () => {
  const user = buildAuthContractUser({
    id: '',
    email: 'admin@sistema.local',
    name: 'Administracion',
    role: 'OWNER',
  });

  assert.equal(user.sub.trim(), '');
});

test('role mapping works for OWNER and TECH', () => {
  const owner = buildAuthContractUser({
    id: 'owner-1',
    email: 'owner@sistema.local',
    name: 'Owner',
    role: 'OWNER',
  });
  const tech = buildAuthContractUser({
    id: 'tech-1',
    email: 'tech@sistema.local',
    name: 'Tech',
    role: 'TECH',
  });

  assert.deepEqual(owner.roles, ['SUPER_ADMIN']);
  assert.deepEqual(tech.roles, ['SALES_AGENT']);
});

test('company mapping is not part of the auth payload and leaves user identity stable', () => {
  const user = buildAuthContractUser({
    id: 'user-prod-1',
    email: 'admin@sistema.local',
    name: 'Administracion',
    role: 'OWNER',
  });

  assert.equal(user.id, user.sub);
  assert.equal(user.email, 'admin@sistema.local');
});
