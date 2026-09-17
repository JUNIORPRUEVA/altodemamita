import assert from 'node:assert/strict';
import test from 'node:test';
import {
  LOCKED_INSTALLMENT_FIELDS,
  SERVER_OWNED_INSTALLMENT_FIELDS,
  resolveIncomingInstallmentStatus,
  resolveServerOwnedInstallmentFinancials,
} from './sync.routes';

/**
 * P0 PROPIEDAD DEL SERVIDOR — ESTADO FINANCIERO DE LA CUOTA (PARTE 6/7).
 *
 * Un upload generico (`POST /sync/upload`) NO establece el estado financiero de
 * una cuota: `paidAmount`, `paidPrincipalAmount`, `paidInterestAmount` y
 * `status` los deriva el servidor desde las operaciones de pago.
 *
 * Contrato vigente:
 *  - Cuota EXISTENTE: los valores del servidor ganan siempre (el snapshot no
 *    puede crear, aumentar ni reducir `paidAmount`, ni forzar `pagada`/`parcial`).
 *  - Cuota NUEVA: arranque canonico (`paidAmount = 0`, estado sin dinero); el
 *    dinero entra como `Payment` por `AuthoritativePaymentService`.
 *  - La proteccion es INDEPENDIENTE de `version`: el cliente no puede
 *    autoproclamarse autoridad enviando una version mayor o igual.
 *  - El snapshot no se rechaza por esto: se ignora el campo y el ACK devuelve
 *    el valor autoritativo, para que el cliente converja.
 *  - `vencida` no es persistible (se normaliza, no se rechaza, por
 *    compatibilidad con clientes legados).
 */

// ---------------------------------------------------------------------------
// Cuota EXISTENTE: el servidor es dueño del estado financiero
// ---------------------------------------------------------------------------

test('6.1 server paid=10000 / client paid=0 -> sigue 10000', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '10000', status: 'parcial' },
    incoming: { paidAmount: '0', status: 'pendiente' },
  });

  assert.equal(result.paidAmount, 10000);
  assert.equal(result.status, 'parcial');
  assert.deepEqual(result.ignoredFields, ['paidAmount', 'status']);
});

test('6.2 server paid=10000 / client paid=999999 -> sigue 10000', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '10000', status: 'parcial' },
    incoming: { paidAmount: '999999', status: 'pagada' },
  });

  assert.equal(result.paidAmount, 10000);
  assert.equal(result.status, 'parcial');
  assert.deepEqual(result.ignoredFields, ['paidAmount', 'status']);
});

test('6.3 server paid=0 / client paid=5000 -> sigue 0', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '0', status: 'pendiente' },
    incoming: { paidAmount: '5000', status: 'parcial' },
  });

  assert.equal(result.paidAmount, 0);
  assert.equal(result.status, 'pendiente');
  assert.deepEqual(result.ignoredFields, ['paidAmount', 'status']);
});

test('6.4 client status=pagada sin pago: no se aplica', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '0', status: 'pendiente' },
    incoming: { paidAmount: '0', status: 'pagada' },
  });

  assert.equal(result.status, 'pendiente');
  assert.deepEqual(result.ignoredFields, ['status']);
});

test('6.5 client status=parcial sin pago: no se aplica', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '0', status: 'pendiente' },
    incoming: { paidAmount: '0', status: 'parcial' },
  });

  assert.equal(result.status, 'pendiente');
  assert.deepEqual(result.ignoredFields, ['status']);
});

test('6.6 client version=999999 no bypassea (la funcion no recibe version)', () => {
  // Un cliente con version 999999 produce exactamente la misma decision.
  const conVersionFalsa = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '10000', status: 'pagada' },
    incoming: { paidAmount: '0', status: 'pendiente' },
  });

  assert.equal(conVersionFalsa.paidAmount, 10000);
  assert.equal(conVersionFalsa.status, 'pagada');
  assert.equal(
    resolveServerOwnedInstallmentFinancials.length,
    1,
    'un unico argumento: sin version',
  );
});

test('6.7 paidPrincipalAmount/paidInterestAmount tambien son server-owned', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: {
      paidAmount: '5000',
      paidPrincipalAmount: '4000',
      paidInterestAmount: '1000',
      status: 'parcial',
    },
    incoming: {
      paidAmount: '5000',
      paidPrincipalAmount: '999999',
      paidInterestAmount: '999999',
      status: 'parcial',
    },
  });

  assert.equal(result.paidPrincipalAmount, 4000);
  assert.equal(result.paidInterestAmount, 1000);
  assert.deepEqual(result.ignoredFields, [
    'paidPrincipalAmount',
    'paidInterestAmount',
  ]);
});

test('6.8 snapshot identico: no hay campos ignorados (sin falso positivo)', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: {
      paidAmount: '7230.94',
      paidPrincipalAmount: '6000',
      paidInterestAmount: '1230.94',
      status: 'pagada',
    },
    incoming: {
      paidAmount: '7230.94',
      paidPrincipalAmount: '6000',
      paidInterestAmount: '1230.94',
      status: 'pagada',
    },
  });

  assert.deepEqual(result.ignoredFields, []);
  assert.equal(result.paidAmount, 7230.94);
});

test('6.9 un cliente legacy que omite los campos no genera ruido', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '1000', status: 'parcial' },
    incoming: {},
  });

  assert.deepEqual(result.ignoredFields, []);
  assert.equal(result.paidAmount, 1000);
  assert.equal(result.status, 'parcial');
});

test('6.10 `vencida` nunca se persiste: se normaliza desde el dinero del servidor', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '0', status: 'vencida', totalAmount: '7230.94' },
    incoming: { status: 'vencida' },
  });

  assert.equal(result.status, 'pendiente');

  const partiallyPaid = resolveServerOwnedInstallmentFinancials({
    existing: { paidAmount: '1000', status: 'vencida', totalAmount: '7230.94' },
    incoming: {},
  });
  assert.equal(partiallyPaid.status, 'parcial');
});

test('6.11 todos los campos financieros declarados son cubiertos', () => {
  assert.deepEqual([...SERVER_OWNED_INSTALLMENT_FIELDS], [
    'paidAmount',
    'paidPrincipalAmount',
    'paidInterestAmount',
    'status',
  ]);

  const result = resolveServerOwnedInstallmentFinancials({
    existing: {
      paidAmount: '0',
      paidPrincipalAmount: '0',
      paidInterestAmount: '0',
      status: 'pendiente',
    },
    incoming: {
      paidAmount: '10',
      paidPrincipalAmount: '10',
      paidInterestAmount: '10',
      status: 'pagada',
    },
  });

  assert.deepEqual(
    result.ignoredFields,
    [...SERVER_OWNED_INSTALLMENT_FIELDS],
    'ningun campo financiero puede escapar del guard',
  );
});

// ---------------------------------------------------------------------------
// Cuota NUEVA: arranque canonico (el dinero entra como Payment)
// ---------------------------------------------------------------------------

test('7.1 una cuota nueva NO puede nacer con paidAmount', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: null,
    incoming: { paidAmount: '5000', status: 'pendiente' },
  });

  assert.equal(result.paidAmount, 0);
  assert.equal(result.paidPrincipalAmount, 0);
  assert.equal(result.paidInterestAmount, 0);
  assert.equal(result.status, 'pendiente');
  assert.deepEqual(result.ignoredFields, ['paidAmount']);
});

test('7.2 una cuota nueva no puede nacer pagada ni parcial', () => {
  for (const status of ['pagada', 'parcial']) {
    const result = resolveServerOwnedInstallmentFinancials({
      existing: null,
      incoming: { paidAmount: '7230.94', status },
    });
    assert.equal(result.status, 'pendiente', `${status} no debe persistirse`);
    assert.equal(result.paidAmount, 0);
  }
});

test('7.3 una cuota nueva no puede nacer con atraso derivado', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: null,
    incoming: { paidAmount: '0', status: 'vencida' },
  });

  assert.equal(result.status, 'pendiente');
});

test('7.4 los estados terminales sin dinero si se preservan', () => {
  for (const status of ['ajustada', 'cancelada']) {
    const result = resolveServerOwnedInstallmentFinancials({
      existing: null,
      incoming: { paidAmount: '0', status },
    });
    assert.equal(result.status, status);
    assert.deepEqual(
      result.ignoredFields,
      [],
      `${status} es terminal y no afirma dinero`,
    );
  }
});

test('7.5 una cuota nueva canonica (0 / pendiente) no reporta campos ignorados', () => {
  const result = resolveServerOwnedInstallmentFinancials({
    existing: null,
    incoming: { paidAmount: '0', status: 'pendiente', totalAmount: '5000' },
  });

  assert.equal(result.paidAmount, 0);
  assert.equal(result.status, 'pendiente');
  assert.deepEqual(result.ignoredFields, []);
});

// ---------------------------------------------------------------------------
// Guards que siguen vigentes
// ---------------------------------------------------------------------------

test('A8 derived vencida: se normaliza y no se persiste como estado autoritativo', () => {
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: '0',
      totalAmount: '7230.94',
    }),
    'pendiente',
  );
  assert.equal(
    resolveIncomingInstallmentStatus({
      incomingStatus: 'vencida',
      paidAmount: '7230.94',
      totalAmount: '7230.94',
    }),
    'pagada',
  );
});

test('A9/F los campos estructurales siguen bloqueados por el upload generico', () => {
  for (const field of [
    'dueDate',
    'installmentNumber',
    'openingBalance',
    'principalAmount',
    'interestAmount',
    'totalAmount',
    'endingBalance',
    'saleSyncId',
  ]) {
    assert.ok(
      (LOCKED_INSTALLMENT_FIELDS as readonly string[]).includes(field),
      `${field} debe estar bloqueado`,
    );
  }
});
