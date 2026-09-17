import assert from 'node:assert/strict';
import test from 'node:test';
import { Prisma } from '@prisma/client';
import {
  offlinePaymentIdempotencyKey,
  readRawSourceSyncId,
  resolvePaymentUploadRoute,
} from './sync.routes';
import {
  applyToInstallment,
  authoritativePaymentRaw,
  resolveInstallmentsToProcess,
} from '../services/authoritativePayment.service';

/**
 * P0 BRIDGE FINANCIERO — PAYMENT SYNC -> SERVICIO AUTORITATIVO.
 *
 * Contrato:
 *  - Un pago offline VALIDO no entra como snapshot: entra por
 *    `AuthoritativePaymentService.registerPayment` (PARTE 3).
 *  - Un pago RECHAZADO no escribe nada ni se confirma (PARTE 5).
 *  - Reintentar la MISMA intencion produce UNA sola operacion financiera
 *    (PARTE 4): la llave idempotente se deriva del `sync_id` de la intencion.
 *  - Una sola intencion puede producir N filas autoritativas (1->N, PARTE 2),
 *    todas correlacionadas con la intencion de origen.
 */

const installment = {
  id: 'inst-1',
  companyId: 'company-1',
  syncId: 'installment-sync-1',
  saleId: 'sale-1',
  saleSyncId: 'sale-sync-1',
  installmentNumber: 1,
  dueDate: new Date(2026, 0, 1),
  openingBalance: new Prisma.Decimal(100000),
  principalAmount: new Prisma.Decimal(8000),
  interestAmount: new Prisma.Decimal(2000),
  totalAmount: new Prisma.Decimal(10000),
  paidAmount: new Prisma.Decimal(0),
  paidPrincipalAmount: new Prisma.Decimal(0),
  paidInterestAmount: new Prisma.Decimal(0),
  status: 'pendiente',
  raw: null,
  version: 1,
  deletedAt: null,
  createdAt: new Date(),
  updatedAt: new Date(),
  endingBalance: new Prisma.Decimal(92000),
};

// ---------------------------------------------------------------------------
// PARTE 3 — ruta del pago
// ---------------------------------------------------------------------------

test('PARTE 3: un pago offline valido se aplica por el servicio autoritativo', () => {
  const decision = resolvePaymentUploadRoute({
    syncId: 'offline-123',
    deletedAt: null,
    missingDependencies: [],
    hasReceivedByUser: true,
  });

  assert.deepEqual(
    decision,
    { route: 'authoritative' },
    'el pago financiero NO puede entrar como snapshot crudo',
  );
});

test('PARTE 3: una fila sin sync_id no se escribe ni se confirma', () => {
  assert.deepEqual(resolvePaymentUploadRoute({ syncId: null }), { route: 'skip' });
  assert.deepEqual(resolvePaymentUploadRoute({ syncId: '   ' }), { route: 'skip' });
});

test('PARTE 3: un soft delete sigue siendo tombstone (no mueve dinero)', () => {
  const decision = resolvePaymentUploadRoute({
    syncId: 'offline-123',
    deletedAt: new Date(2026, 0, 5),
  });

  assert.deepEqual(
    decision,
    { route: 'legacy_tombstone' },
    'borrar un pago no puede registrarlo como cobro',
  );
});

// ---------------------------------------------------------------------------
// PARTE 5 — rechazo: no hay escritura ni ACK
// ---------------------------------------------------------------------------

test('PARTE 5: una dependencia faltante rechaza el pago sin escribir nada', () => {
  const decision = resolvePaymentUploadRoute({
    syncId: 'offline-123',
    deletedAt: null,
    missingDependencies: ['saleSyncId'],
    hasReceivedByUser: true,
  });

  assert.equal(decision.route, 'reject');
  assert.equal(decision.reason, 'missing_dependency');
  assert.deepEqual(decision.missingFields, ['saleSyncId']);
  assert.match(
    decision.route === 'reject' ? decision.message : '',
    /saleSyncId/,
  );
});

test('PARTE 5: sin usuario receptor tampoco hay pago (rechazo, no ACK)', () => {
  const decision = resolvePaymentUploadRoute({
    syncId: 'offline-123',
    deletedAt: null,
    missingDependencies: [],
    hasReceivedByUser: false,
  });

  assert.equal(decision.route, 'reject');
  assert.equal(decision.reason, 'missing_dependency');
  assert.deepEqual(decision.missingFields, ['receivedByUserId']);
});

test('PARTE 5: un rechazo nunca se convierte en ruta autoritativa', () => {
  const rejected = resolvePaymentUploadRoute({
    syncId: 'offline-123',
    missingDependencies: ['clientSyncId', 'installmentSyncId'],
  });

  assert.notEqual(rejected.route, 'authoritative');
});

// ---------------------------------------------------------------------------
// PARTE 4 — reintentos: una sola operacion financiera
// ---------------------------------------------------------------------------

test('PARTE 4: la misma intencion enviada 10 veces produce UNA operacion', () => {
  const keys = new Set<string>();
  for (let attempt = 0; attempt < 10; attempt += 1) {
    keys.add(offlinePaymentIdempotencyKey('company-1', 'offline-123'));
  }

  assert.equal(keys.size, 1, 'la llave debe ser estable en los reintentos');
});

test('PARTE 4: la llave no colisiona entre intenciones ni entre companias', () => {
  const base = offlinePaymentIdempotencyKey('company-1', 'offline-123');

  assert.notEqual(base, offlinePaymentIdempotencyKey('company-1', 'offline-124'));
  assert.notEqual(base, offlinePaymentIdempotencyKey('company-2', 'offline-123'));
  assert.notEqual(base, offlinePaymentIdempotencyKey('company-1', 'payment-abc'));
});

// ---------------------------------------------------------------------------
// PARTE 2 — 1 -> N y correlacion
// ---------------------------------------------------------------------------

test('PARTE 2: una intencion grande impacta N cuotas (mecanismo 1->N)', () => {
  const segundo = {
    ...installment,
    id: 'inst-2',
    syncId: 'installment-sync-2',
    installmentNumber: 2,
    dueDate: new Date(2026, 1, 1),
  };
  const tercero = {
    ...installment,
    id: 'inst-3',
    syncId: 'installment-sync-3',
    installmentNumber: 3,
    dueDate: new Date(2026, 2, 1),
  };
  // Las tres cuotas estan vencidas frente a la fecha del pago.
  const paymentDate = new Date(2026, 3, 2);

  const seleccionadas = resolveInstallmentsToProcess({
    installments: [installment, segundo, tercero],
    paymentDate,
    paymentTypeOverride: 'todas_cuotas_vencidas',
  });
  assert.equal(seleccionadas.length, 3, 'una intencion cubre las 3 cuotas');

  const aplicaciones = seleccionadas.map((item) =>
    applyToInstallment(item, 10000, paymentDate),
  );

  assert.equal(
    aplicaciones.length,
    3,
    'el servicio deriva N filas de pago a partir de UNA intencion',
  );
  for (const outcome of aplicaciones) {
    assert.ok(
      outcome.appliedAmount > 0,
      'cada cuota impactada la actualiza el SERVICIO, no el snapshot',
    );
  }
});

test('PARTE 2: las N filas del split conservan la MISMA intencion de origen', () => {
  const filas = [
    authoritativePaymentRaw('offline-123'),
    authoritativePaymentRaw('offline-123'),
    authoritativePaymentRaw('offline-123'),
  ];

  for (const raw of filas) {
    assert.equal(readRawSourceSyncId(raw), 'offline-123');
  }
  // La correlacion no es la identidad de la fila: el `syncId` lo genera el
  // servicio por cada fila creada (por eso 1->N no se colapsa).
  for (const raw of filas) {
    assert.equal(Object.hasOwn(raw, 'syncId'), false);
  }
});

test('PARTE 2: un pago creado online no arrastra intencion de origen', () => {
  assert.equal(readRawSourceSyncId(authoritativePaymentRaw(null)), null);
});
