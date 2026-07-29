import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { resolvePaymentReminderRecipients } from './paymentReminderRecipients.service';

const testNumbers = ['18295344286', '18295319442'];

describe('resolvePaymentReminderRecipients', () => {
  it('redirige modo prueba exactamente a los dos numeros autorizados', () => {
    const resolved = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers,
    });

    assert.equal(resolved.mode, 'TEST');
    assert.equal(resolved.redirected, true);
    assert.equal(resolved.originalRecipient, '18095551234');
    assert.equal(resolved.originalRecipientMasked, '***1234');
    assert.deepEqual(resolved.recipients, testNumbers);
    assert.equal(resolved.recipients.includes('18095551234'), false);
  });

  it('bloquea produccion si los destinatarios reales no estan permitidos', () => {
    const resolved = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: false,
      allowRealRecipients: false,
      testNumbers,
    });

    assert.equal(resolved.mode, 'BLOCKED');
    assert.equal(resolved.reason, 'REAL_RECIPIENTS_BLOCKED');
    assert.deepEqual(resolved.recipients, []);
  });

  it('permite produccion solo con allowRealRecipients=true', () => {
    const resolved = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: false,
      allowRealRecipients: true,
      testNumbers,
    });

    assert.equal(resolved.mode, 'PRODUCTION');
    assert.deepEqual(resolved.recipients, ['18095551234']);
  });

  it('rechaza listas vacias, invalidas y duplicadas de prueba', () => {
    assert.equal(resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: [],
    }).mode, 'BLOCKED');

    assert.throws(() => resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['555'],
    }), /invalido/);

    assert.throws(() => resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['18295344286', '8295344286'],
    }), /duplicados/);
  });
});
