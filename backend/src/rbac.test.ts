import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canonicalActions,
  canonicalPermissionAction,
  canonicalPermissionModule,
  contractPermissionCodes,
  mapAllows,
  ownerPermissionCodes,
  permissionGrantsPaymentCancellation,
} from './rbac';

test('normaliza recursos del catalogo en espanol a la nomenclatura canonica', () => {
  assert.equal(canonicalPermissionModule('pagos'), 'payments');
  assert.equal(canonicalPermissionModule('PAGOS'), 'payments');
  assert.equal(canonicalPermissionModule('payments'), 'payments');
  assert.equal(canonicalPermissionModule('ventas'), 'sales');
  assert.equal(canonicalPermissionModule('clientes'), 'clients');
  assert.equal(canonicalPermissionModule('solares'), 'lots');
  assert.equal(canonicalPermissionModule('products'), 'lots');
  assert.equal(canonicalPermissionModule('vendedores'), 'sellers');
  assert.equal(canonicalPermissionModule('cuotas'), 'installments');
  assert.equal(canonicalPermissionModule('usuarios'), 'users');
  assert.equal(canonicalPermissionModule('configuracion'), 'configuration');
  assert.equal(canonicalPermissionModule('backup'), 'configuration');
  assert.equal(canonicalPermissionModule('busqueda'), 'search');
});

test('normaliza acciones del catalogo en espanol a la nomenclatura canonica', () => {
  assert.equal(canonicalPermissionAction('ver'), 'read');
  assert.equal(canonicalPermissionAction('crear'), 'create');
  assert.equal(canonicalPermissionAction('editar'), 'update');
  assert.equal(canonicalPermissionAction('eliminar'), 'delete');
  assert.equal(canonicalPermissionAction('anular'), 'annul');
  assert.equal(canonicalPermissionAction('cancelar'), 'cancel');
  assert.equal(canonicalPermissionAction('read'), 'read');
  assert.equal(canonicalPermissionAction('create'), 'create');
  assert.equal(canonicalPermissionAction('update'), 'update');
  assert.equal(canonicalPermissionAction('delete'), 'delete');
  assert.equal(canonicalPermissionAction('annul'), 'annul');
  assert.equal(canonicalPermissionAction('manage'), 'manage');
  assert.equal(canonicalPermissionAction('accion_inventada'), null);
});

test('las acciones legacy granulares no se amplian entre si', () => {
  const editar = canonicalActions(['editar']);
  assert.equal(editar.has('update'), true);
  assert.equal(editar.has('delete'), false);
  assert.equal(editar.has('create'), false);
  assert.equal(editar.has('annul'), false);

  const crear = canonicalActions(['crear']);
  assert.equal(crear.has('create'), true);
  assert.equal(crear.has('annul'), false);
  assert.equal(crear.has('delete'), false);
});

test('el permiso generico write habilita mutaciones ordinarias pero NUNCA anular', () => {
  const write = canonicalActions(['write']);
  assert.equal(write.has('create'), true);
  assert.equal(write.has('update'), true);
  assert.equal(write.has('delete'), true);
  assert.equal(write.has('annul'), false);
  assert.equal(write.has('cancel'), false);
  assert.equal(write.has('manage'), false);
  assert.equal(write.has('read'), false);
});

test('el comodin no habilita anular ni gestionar', () => {
  const star = canonicalActions(['*']);
  assert.equal(star.has('read'), true);
  assert.equal(star.has('delete'), true);
  assert.equal(star.has('annul'), false);
  assert.equal(star.has('manage'), false);
});

test('anular pagos requiere la accion explicita de anulacion', () => {
  assert.equal(permissionGrantsPaymentCancellation('pagos', ['ver', 'anular']), true);
  assert.equal(permissionGrantsPaymentCancellation('payments', ['annul']), true);
  assert.equal(permissionGrantsPaymentCancellation('PAGOS', ['ANULAR']), true);
  assert.equal(permissionGrantsPaymentCancellation('pagos', ['ver', 'crear', 'editar', 'eliminar']), false);
  assert.equal(permissionGrantsPaymentCancellation('pagos', ['write']), false);
  assert.equal(permissionGrantsPaymentCancellation('pagos', ['*']), false);
  assert.equal(permissionGrantsPaymentCancellation('clientes', ['anular']), false);
  assert.equal(permissionGrantsPaymentCancellation('pagos', []), false);
  assert.equal(permissionGrantsPaymentCancellation(undefined, ['anular']), false);
});

test('el mapa canonico resuelve recurso y accion de forma independiente', () => {
  const map = new Map<string, Set<'read' | 'create' | 'update' | 'delete' | 'annul' | 'cancel' | 'manage'>>([
    ['sales', new Set(['read', 'create'])],
    ['payments', new Set(['read', 'annul'])],
  ]);
  assert.equal(mapAllows(map, 'ventas', 'read'), true);
  assert.equal(mapAllows(map, 'sales', 'create'), true);
  assert.equal(mapAllows(map, 'sales', 'update'), false);
  assert.equal(mapAllows(map, 'sales', 'delete'), false);
  assert.equal(mapAllows(map, 'payments', 'annul'), true);
  assert.equal(mapAllows(map, 'pagos', 'annul'), true);
  assert.equal(mapAllows(map, 'clients', 'read'), false);
});

test('el contrato de TECH expone exactamente los permisos persistidos', () => {
  const map = new Map<string, Set<'read' | 'create' | 'update' | 'delete' | 'annul' | 'cancel' | 'manage'>>([
    ['sales', new Set(['read', 'create'])],
    ['payments', new Set(['annul'])],
  ]);
  const codes = contractPermissionCodes('TECH', map);
  assert.deepEqual(codes, ['payments.annul', 'sales.create', 'sales.read']);
  assert.equal(codes.includes('sales.update'), false);
  assert.equal(codes.includes('sales.delete'), false);
});

test('el contrato de OWNER incluye el catalogo administrativo completo', () => {
  const codes = contractPermissionCodes('OWNER', new Map());
  assert.deepEqual(codes, ownerPermissionCodes);
  assert.equal(codes.includes('payments.annul'), true);
  assert.equal(codes.includes('sales.cancel'), true);
  assert.equal(codes.includes('users.manage'), true);
});
