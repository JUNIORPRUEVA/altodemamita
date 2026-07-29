import { normalizeWhatsappPhone } from './whatsapp.service';

export type PaymentReminderRecipientMode = 'TEST' | 'PRODUCTION' | 'BLOCKED';

export type PaymentReminderRecipients = {
  mode: PaymentReminderRecipientMode;
  originalRecipient: string | null;
  originalRecipientMasked: string | null;
  recipients: string[];
  redirected: boolean;
  reason?: string;
};

export function resolvePaymentReminderRecipients(input: {
  customerPhone?: string | null;
  testMode: boolean;
  allowRealRecipients: boolean;
  testNumbers: string[];
}): PaymentReminderRecipients {
  const originalRecipient = normalizeWhatsappPhone(input.customerPhone);
  const testNumbers = normalizeTestNumbers(input.testNumbers);

  if (input.testMode) {
    if (input.allowRealRecipients) {
      return blocked(originalRecipient, 'TEST_MODE_CANNOT_ALLOW_REAL_RECIPIENTS');
    }
    if (testNumbers.length === 0) {
      return blocked(originalRecipient, 'EMPTY_TEST_NUMBERS');
    }
    return {
      mode: 'TEST',
      originalRecipient,
      originalRecipientMasked: maskPhone(originalRecipient),
      recipients: testNumbers,
      redirected: true,
    };
  }

  if (!input.allowRealRecipients) {
    return blocked(originalRecipient, 'REAL_RECIPIENTS_BLOCKED');
  }
  if (!originalRecipient) {
    return blocked(originalRecipient, 'INVALID_CUSTOMER_PHONE');
  }

  return {
    mode: 'PRODUCTION',
    originalRecipient,
    originalRecipientMasked: maskPhone(originalRecipient),
    recipients: [originalRecipient],
    redirected: false,
  };
}

export function normalizeTestNumbers(values: string[]) {
  const normalized = values.map((value) => normalizeWhatsappPhone(value));
  if (normalized.some((value) => !value)) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS contiene un numero invalido.');
  }
  const unique = [...new Set(normalized.filter((value): value is string => Boolean(value)))];
  if (unique.length !== normalized.length) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS no puede contener duplicados.');
  }
  return unique;
}

export function maskPhone(phone?: string | null) {
  if (!phone) return null;
  return `***${phone.slice(-4)}`;
}

function blocked(originalRecipient: string | null, reason: string): PaymentReminderRecipients {
  return {
    mode: 'BLOCKED',
    originalRecipient,
    originalRecipientMasked: maskPhone(originalRecipient),
    recipients: [],
    redirected: false,
    reason,
  };
}
