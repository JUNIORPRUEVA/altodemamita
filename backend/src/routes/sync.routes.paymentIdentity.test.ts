import assert from 'node:assert/strict';
import test from 'node:test';
import { offlinePaymentIdempotencyKey, readRawSourceSyncId } from './sync.routes';
import { authoritativePaymentRaw } from '../services/authoritativePayment.service';

/**
 * P0 IDENTIDAD FINANCIERA
 *
 * `Payment.syncId` identifica la FILA autoritativa.
 * `raw.sourceSyncId` / `source_payment_sync_id` identifica la INTENCION del
 * cliente que la origino, porque una intencion puede producir N filas.
 *
 * Estos tests congelan el contrato de correlacion (metadata pura: sin reglas
 * financieras y sin migracion, porque se guarda en el JSON `raw` existente).
 */

test('B1: el raw autoritativo persiste la intencion de origen sin migracion', () => {
  const withSource = authoritativePaymentRaw('offline-001');
  assert.equal(withSource.authoritativeSource, 'phase_1d');
  assert.equal(withSource.sourceSyncId, 'offline-001');

  // Los pagos creados online directo no llevan intencion.
  const online = authoritativePaymentRaw(null);
  assert.equal(online.authoritativeSource, 'phase_1d');
  assert.equal(Object.hasOwn(online, 'sourceSyncId'), false);

  const blank = authoritativePaymentRaw('   ');
  assert.equal(Object.hasOwn(blank, 'sourceSyncId'), false);
});

test('B2: split 1->N conserva la MISMA intencion en las N filas', () => {
  // El servicio crea una fila por aplicacion a cuota (+1 por capital); todas
  // deben correlacionar con la intencion original.
  const rows = [
    authoritativePaymentRaw('offline-001'),
    authoritativePaymentRaw('offline-001'),
    authoritativePaymentRaw('offline-001'),
  ];
  // Las N filas correlacionan con la MISMA intencion.
  const ids = new Set(rows.map((raw) => readRawSourceSyncId(raw)));
  assert.deepEqual([...ids], ['offline-001']);
  for (const raw of rows) {
    assert.equal(readRawSourceSyncId(raw), 'offline-001');
  }
  // La correlacion NO es la identidad de la fila: el raw no lleva un syncId.
  for (const raw of rows) {
    assert.equal(Object.hasOwn(raw, 'syncId'), false);
  }
});

test('B3: el payload de descarga expone la intencion normalizada', () => {
  assert.equal(
    readRawSourceSyncId({ authoritativeSource: 'phase_1d', sourceSyncId: 'offline-001' }),
    'offline-001',
  );
  // Pagos online: sin intencion de origen.
  assert.equal(readRawSourceSyncId({ authoritativeSource: 'phase_1d' }), null);
  assert.equal(readRawSourceSyncId(null), null);
  assert.equal(readRawSourceSyncId('texto'), null);
  assert.equal(readRawSourceSyncId({ sourceSyncId: '   ' }), null);
  // No muta el objeto original.
  const raw = { authoritativeSource: 'phase_1d', sourceSyncId: 'offline-001' };
  readRawSourceSyncId(raw);
  assert.deepEqual(raw, { authoritativeSource: 'phase_1d', sourceSyncId: 'offline-001' });
});

test('B4: reintentos de la misma intencion producen una clave de operacion estable', () => {
  assert.equal(
    offlinePaymentIdempotencyKey('company-1', 'offline-001'),
    offlinePaymentIdempotencyKey('company-1', 'offline-001'),
  );
  assert.notEqual(
    offlinePaymentIdempotencyKey('company-1', 'offline-001'),
    offlinePaymentIdempotencyKey('company-2', 'offline-001'),
  );
  assert.notEqual(
    offlinePaymentIdempotencyKey('company-1', 'offline-001'),
    offlinePaymentIdempotencyKey('company-1', 'offline-002'),
  );
});

test('B5: la metadata de correlacion no altera ninguna regla financiera', () => {
  // El helper solo transforma datos: con/sin intencion, el resto del raw es
  // identico (no toca importes, estados ni calendario).
  const without = authoritativePaymentRaw(undefined);
  const withSource = authoritativePaymentRaw('offline-001');
  const { sourceSyncId, ...rest } = withSource as Record<string, unknown> & {
    sourceSyncId?: string;
  };
  assert.equal(sourceSyncId, 'offline-001');
  assert.deepEqual(rest, without);
});
