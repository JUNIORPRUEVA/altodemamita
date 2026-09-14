import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { config } from '../config';
import {
  effectiveReminderEnabled,
  isWhatsappProviderConfigured,
} from './paymentReminderAdmin.service';

const originalConfig = {
  enabled: config.paymentRemindersEnabled,
  emergencyStop: config.paymentRemindersEmergencyStop,
  dryRun: config.paymentRemindersDryRun,
  testMode: config.paymentRemindersTestMode,
  allowRealRecipients: config.paymentRemindersAllowRealRecipients,
  accessToken: config.whatsappAccessToken,
  phoneNumberId: config.whatsappPhoneNumberId,
  businessAccountId: config.whatsappBusinessAccountId,
};

describe('payment reminder admin safety status', () => {
  afterEach(() => {
    config.paymentRemindersEnabled = originalConfig.enabled;
    config.paymentRemindersEmergencyStop = originalConfig.emergencyStop;
    config.paymentRemindersDryRun = originalConfig.dryRun;
    config.paymentRemindersTestMode = originalConfig.testMode;
    config.paymentRemindersAllowRealRecipients = originalConfig.allowRealRecipients;
    config.whatsappAccessToken = originalConfig.accessToken;
    config.whatsappPhoneNumberId = originalConfig.phoneNumberId;
    config.whatsappBusinessAccountId = originalConfig.businessAccountId;
  });

  it('requires all Meta provider values before considering WhatsApp configured', () => {
    config.whatsappAccessToken = 'token-present';
    config.whatsappPhoneNumberId = '1234567890';
    config.whatsappBusinessAccountId = '';

    assert.equal(isWhatsappProviderConfigured(), false);

    config.whatsappBusinessAccountId = '9876543210';

    assert.equal(isWhatsappProviderConfigured(), true);
  });

  it('marks effective sending active only when every production gate allows real recipients', () => {
    config.paymentRemindersEnabled = true;
    config.paymentRemindersEmergencyStop = false;
    config.paymentRemindersDryRun = false;
    config.paymentRemindersTestMode = false;
    config.paymentRemindersAllowRealRecipients = true;
    config.whatsappAccessToken = 'token-present';
    config.whatsappPhoneNumberId = '1234567890';
    config.whatsappBusinessAccountId = '9876543210';

    assert.equal(effectiveReminderEnabled(true), true);

    config.paymentRemindersDryRun = true;

    assert.equal(effectiveReminderEnabled(true), false);
  });
});
