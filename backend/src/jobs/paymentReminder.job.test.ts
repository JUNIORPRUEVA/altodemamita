import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { isPaymentReminderSendWindowOpen } from '../services/paymentReminderWindow.service';

describe('isPaymentReminderSendWindowOpen', () => {
  it('permite lunes a sabado entre 9:00 y 5:00 hora dominicana desde la fecha de inicio', () => {
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-07-29T13:00:00.000Z')), true);
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-07-29T20:59:00.000Z')), true);
  });

  it('bloquea antes de las 9, desde las 5, domingos y antes de la fecha de inicio', () => {
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-07-29T12:59:00.000Z')), false);
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-07-29T21:00:00.000Z')), false);
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-08-02T14:00:00.000Z')), false);
    assert.equal(isPaymentReminderSendWindowOpen(new Date('2026-07-28T14:00:00.000Z')), false);
  });
});
