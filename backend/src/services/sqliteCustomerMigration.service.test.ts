import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import {
  classifyBusinessConfigKey,
  deterministicUuid,
  normalizeMoneyString,
  normalizeActiveSaleBalances,
  runPrecheck,
  sumNormalizedMoney,
} from './sqliteCustomerMigration.service';

test('normalizes SQLite REAL money per row before totals', () => {
  assert.equal(normalizeMoneyString(0.1 + 0.2), '0.30');
  assert.equal(normalizeMoneyString(100.10000000000001), '100.10');
  const rows = Array.from({ length: 1000 }, () => ({ amount: 0.1 + 0.2 }));
  assert.equal(sumNormalizedMoney(rows, 'amount').toFixed(2), '300.00');
});

test('classifies business configuration keys with fail-closed unknowns', () => {
  assert.equal(classifyBusinessConfigKey('business_name'), 'CLOUD_BUSINESS');
  assert.equal(classifyBusinessConfigKey('currency_symbol'), 'CLOUD_BUSINESS');
  assert.equal(classifyBusinessConfigKey('default_payment_method'), 'CLOUD_BUSINESS');
  assert.equal(classifyBusinessConfigKey('sale_default_monthly_interest'), 'CLOUD_BUSINESS');
  assert.equal(classifyBusinessConfigKey('auth.last_cloud_validation_at'), 'AUTH_SESSION');
  assert.equal(classifyBusinessConfigKey('sync.last_run_at'), 'SYNC_RUNTIME');
  assert.equal(classifyBusinessConfigKey('backend_url'), 'LEGACY_TECHNICAL_CONFIG');
  assert.equal(classifyBusinessConfigKey('database_host'), 'LEGACY_TECHNICAL_CONFIG');
  assert.equal(classifyBusinessConfigKey('old_sync_token'), 'LEGACY_TECHNICAL_CONFIG');
  assert.equal(classifyBusinessConfigKey('printer.default'), 'PRINTER_LOCAL');
  assert.equal(classifyBusinessConfigKey('mystery_key'), 'UNKNOWN');
});

test('deterministic UUIDs are stable for migration identity mapping', () => {
  assert.equal(deterministicUuid('sale', 'sale-1'), deterministicUuid('sale', 'sale-1'));
  assert.notEqual(deterministicUuid('sale', 'sale-1'), deterministicUuid('sale', 'sale-2'));
});

test('normalizes active sale balance residuals into final eligible installment', () => {
  const bundle = {
    ventas: [
      { id: 1, sync_id: 'sale-1', estado: 'activa', saldo_pendiente: 100.01 },
      { id: 2, sync_id: 'sale-2', estado: 'pagada', saldo_pendiente: 0 },
    ],
    cuotas: [
      { id: 1, sync_id: 'installment-1', venta_id: 1, numero_cuota: 1, capital_cuota: 33.33, capital_pagado: 0, monto_cuota: 34.33, estado: 'pendiente' },
      { id: 2, sync_id: 'installment-2', venta_id: 1, numero_cuota: 2, capital_cuota: 33.33, capital_pagado: 0, monto_cuota: 34.33, estado: 'pendiente' },
      { id: 3, sync_id: 'installment-3', venta_id: 1, numero_cuota: 3, capital_cuota: 33.33, capital_pagado: 0, monto_cuota: 34.33, estado: 'pendiente' },
      { id: 4, sync_id: 'installment-4', venta_id: 2, numero_cuota: 1, capital_cuota: 10, capital_pagado: 10, monto_cuota: 11, estado: 'pagada' },
    ],
  };

  const report = normalizeActiveSaleBalances(bundle);

  assert.equal(report.status, 'PASS');
  assert.equal(report.affectedActiveSales, 1);
  assert.equal(report.normalizedSales, 1);
  assert.equal(report.unexplainedSales, 0);
  assert.equal(report.sumAbsoluteDelta, '0.02');
  assert.equal(bundle.cuotas[2].capital_cuota, '33.35');
  assert.equal(bundle.cuotas[2].monto_cuota, '34.35');
});

test('blocks active sale balance residuals without eligible installment', () => {
  const bundle = {
    ventas: [{ id: 1, sync_id: 'sale-1', estado: 'activa', saldo_pendiente: 10.02 }],
    cuotas: [{ id: 1, sync_id: 'installment-1', venta_id: 1, numero_cuota: 1, capital_cuota: 10, capital_pagado: 10, monto_cuota: 11, estado: 'pagada' }],
  };

  const report = normalizeActiveSaleBalances(bundle);

  assert.equal(report.status, 'BLOCKING');
  assert.equal(report.unexplainedSales, 1);
});

test('precheck blocks duplicate sync IDs, orphan payments, duplicate active sales, invalid money, and unknown config', () => {
  const root = mkdtempSync(join(process.cwd(), 'tmp_migration_test_'));
  try {
    const db = join(root, 'fixture.db');
    createFixture(db);
    execFileSync('sqlite3', [db, "INSERT INTO clientes (id, sync_id, nombre, deleted_at) VALUES (2, 'client-1', 'Dup', NULL);"]);
    execFileSync('sqlite3', [db, "INSERT INTO pagos (id, sync_id, venta_id, cliente_id, cuota_id, monto_pagado, tipo_pago, deleted_at) VALUES (2, 'payment-2', 999, 1, 1, 10, 'cuota', NULL);"]);
    execFileSync('sqlite3', [db, "INSERT INTO ventas (id, sync_id, cliente_id, solar_id, usuario_id, fecha_venta, precio_venta, saldo_pendiente, estado, deleted_at) VALUES (2, 'sale-2', 1, 1, 1, '2026-01-01', -1, 0, 'activa', NULL);"]);
    execFileSync('sqlite3', [db, "INSERT INTO configuracion (clave, valor, fecha_actualizacion) VALUES ('mystery_key', 'x', '2026-01-01');"]);

    const report = runPrecheck(db);

    assert.equal(report.status, 'BLOCKING');
    assert.match(report.messages.join('\n'), /clientes\.sync_id duplicate groups/);
    assert.match(report.messages.join('\n'), /pagos\.venta_id orphans/);
    assert.match(report.messages.join('\n'), /duplicate active sale per lot/);
    assert.match(report.messages.join('\n'), /ventas invalid\/null money/);
    assert.match(report.messages.join('\n'), /Unknown configuracion keys/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

function createFixture(db: string) {
  execFileSync('sqlite3', [db, `
    PRAGMA user_version = 28;
    CREATE TABLE clientes (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, cedula TEXT, telefono TEXT, direccion TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE vendedores (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, cedula TEXT, telefono TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE solares (id INTEGER PRIMARY KEY, sync_id TEXT, manzana_numero TEXT, solar_numero TEXT, metros_cuadrados REAL, precio_por_metro REAL, estado TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE usuarios (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, email TEXT, rol TEXT, password_hash TEXT, activo INTEGER, deleted_at TEXT, version INTEGER);
    CREATE TABLE roles (id INTEGER PRIMARY KEY, sync_id TEXT, code TEXT, name TEXT, description TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE permisos (id INTEGER PRIMARY KEY, sync_id TEXT, usuario_id INTEGER, modulo TEXT, acciones TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE user_roles (id INTEGER PRIMARY KEY, sync_id TEXT, user_id INTEGER, role_id INTEGER, deleted_at TEXT, version INTEGER);
    CREATE TABLE role_permissions (id INTEGER PRIMARY KEY, sync_id TEXT, role_id INTEGER, permission_id INTEGER, deleted_at TEXT, version INTEGER);
    CREATE TABLE company_profiles (id INTEGER PRIMARY KEY, sync_id TEXT, name TEXT, phone TEXT, address TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE informacion_empresa (id INTEGER PRIMARY KEY, sync_id TEXT, nombre TEXT, telefono TEXT, direccion TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE parametros_financieros (id INTEGER PRIMARY KEY, sync_id TEXT, inicial_porcentaje TEXT, interes_mensual TEXT, cantidad_cuotas TEXT, simbolo_moneda TEXT, lugares_decimales TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE configuracion (clave TEXT PRIMARY KEY, valor TEXT, fecha_actualizacion TEXT);
    CREATE TABLE ventas (id INTEGER PRIMARY KEY, sync_id TEXT, cliente_id INTEGER, solar_id INTEGER, usuario_id INTEGER, vendedor_id INTEGER, fecha_venta TEXT, precio_venta REAL, monto_inicial_requerido REAL, monto_inicial_pagado REAL, saldo_financiado REAL, saldo_pendiente REAL, estado TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE cuotas (id INTEGER PRIMARY KEY, sync_id TEXT, venta_id INTEGER, numero_cuota INTEGER, capital_cuota REAL, interes_cuota REAL, monto_cuota REAL, monto_pagado REAL, capital_pagado REAL, interes_pagado REAL, estado TEXT, deleted_at TEXT, version INTEGER);
    CREATE TABLE pagos (id INTEGER PRIMARY KEY, sync_id TEXT, venta_id INTEGER, cliente_id INTEGER, cuota_id INTEGER, monto_pagado REAL, tipo_pago TEXT, deleted_at TEXT, version INTEGER);
    INSERT INTO clientes (id, sync_id, nombre, deleted_at) VALUES (1, 'client-1', 'A', NULL);
    INSERT INTO vendedores (id, sync_id, nombre, deleted_at) VALUES (1, 'seller-1', 'S', NULL);
    INSERT INTO solares (id, sync_id, manzana_numero, solar_numero, metros_cuadrados, precio_por_metro, estado, deleted_at) VALUES (1, 'lot-1', 'A', '1', 100, 100, 'vendido', NULL);
    INSERT INTO usuarios (id, sync_id, nombre, email, rol, password_hash, activo, deleted_at) VALUES (1, 'user-1', 'U', 'u@test.invalid', 'admin', 'hash', 1, NULL);
    INSERT INTO roles (id, sync_id, code, name, deleted_at) VALUES (1, 'role-1', 'ADMIN', 'Admin', NULL);
    INSERT INTO permisos (id, sync_id, usuario_id, modulo, acciones, deleted_at) VALUES (1, 'perm-1', 1, 'ventas', '["ver"]', NULL);
    INSERT INTO user_roles (id, sync_id, user_id, role_id, deleted_at) VALUES (1, 'ur-1', 1, 1, NULL);
    INSERT INTO company_profiles (id, sync_id, name, deleted_at) VALUES (1, 'profile-1', 'Business', NULL);
    INSERT INTO configuracion (clave, valor, fecha_actualizacion) VALUES ('business_name', 'Business', '2026-01-01');
    INSERT INTO ventas (id, sync_id, cliente_id, solar_id, usuario_id, vendedor_id, fecha_venta, precio_venta, monto_inicial_requerido, monto_inicial_pagado, saldo_financiado, saldo_pendiente, estado, deleted_at) VALUES (1, 'sale-1', 1, 1, 1, 1, '2026-01-01', 100, 10, 10, 90, 90, 'activa', NULL);
    INSERT INTO cuotas (id, sync_id, venta_id, numero_cuota, capital_cuota, interes_cuota, monto_cuota, monto_pagado, capital_pagado, interes_pagado, estado, deleted_at) VALUES (1, 'installment-1', 1, 1, 90, 1, 91, 0, 0, 0, 'pendiente', NULL);
    INSERT INTO pagos (id, sync_id, venta_id, cliente_id, cuota_id, monto_pagado, tipo_pago, deleted_at) VALUES (1, 'payment-1', 1, 1, 1, 10, 'cuota', NULL);
  `]);
}
