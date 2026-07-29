import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT ?? 3000),
  jwtSecret: process.env.JWT_SECRET ?? '',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN ?? '12h',
  syncDeviceToken: process.env.SYNC_DEVICE_TOKEN ?? '',
  ownerEmail: process.env.OWNER_EMAIL ?? '',
  ownerPassword: process.env.OWNER_PASSWORD ?? '',
  ownerName: process.env.OWNER_NAME ?? 'Dueno',
  techEmail: process.env.TECH_EMAIL ?? '',
  techPassword: process.env.TECH_PASSWORD ?? '',
  techName: process.env.TECH_NAME ?? 'Tecnico',
  companyTenantKey:
    process.env.COMPANY_TENANT_KEY ?? 'alto-dona-mamita-sistema-solares',
  companyName: process.env.COMPANY_NAME ?? 'EL ALTO DE DONA MAMITA',
  paymentRemindersEnabled:
    String(process.env.PAYMENT_REMINDERS_ENABLED ?? 'false').toLowerCase() === 'true',
  paymentRemindersDryRun:
    String(process.env.PAYMENT_REMINDERS_DRY_RUN ?? 'true').toLowerCase() === 'true',
  paymentRemindersTestMode:
    String(process.env.PAYMENT_REMINDERS_TEST_MODE ?? 'true').toLowerCase() === 'true',
  paymentRemindersTestNumbers:
    process.env.PAYMENT_REMINDERS_TEST_NUMBERS ?? '18295344286,18295319442',
  paymentRemindersAllowRealRecipients:
    String(process.env.PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS ?? 'false').toLowerCase() === 'true',
  lateFeeDailyRate: process.env.LATE_FEE_DAILY_RATE ?? '0.01',
  paymentReminderCron: process.env.PAYMENT_REMINDER_CRON ?? '0 9 * * *',
  paymentReminderTimezone: process.env.PAYMENT_REMINDER_TIMEZONE ?? 'America/Santo_Domingo',
  paymentReminderWindowStartHour: Number(process.env.PAYMENT_REMINDER_WINDOW_START_HOUR ?? 9),
  paymentReminderWindowEndHour: Number(process.env.PAYMENT_REMINDER_WINDOW_END_HOUR ?? 17),
  paymentReminderAllowedDays:
    process.env.PAYMENT_REMINDER_ALLOWED_DAYS ?? '1,2,3,4,5,6',
  paymentReminderStartDate: process.env.PAYMENT_REMINDER_START_DATE ?? '',
  whatsappPaymentTemplate:
    process.env.WHATSAPP_PAYMENT_TEMPLATE ?? 'recordatorio_cuotas_vencidas_detalle5',
  whatsappPaymentTestTemplate:
    process.env.WHATSAPP_PAYMENT_TEST_TEMPLATE ?? 'recordatorio_cuotas_vencidas_detalle5',
  whatsappTemplateLanguage: process.env.WHATSAPP_TEMPLATE_LANGUAGE ?? 'es',
  whatsappAccessToken: process.env.WHATSAPP_ACCESS_TOKEN ?? '',
  whatsappPhoneNumberId: process.env.WHATSAPP_PHONE_NUMBER_ID ?? '',
  whatsappBusinessAccountId: process.env.WHATSAPP_BUSINESS_ACCOUNT_ID ?? '',
};

export function validateConfig() {
  const missing = [];
  if (!process.env.DATABASE_URL || process.env.DATABASE_URL.trim().length === 0) {
    missing.push('DATABASE_URL');
  }
  const rate = Number(config.lateFeeDailyRate);
  if (!Number.isFinite(rate) || rate !== 0.01) {
    throw new Error('LATE_FEE_DAILY_RATE debe ser exactamente 0.01 para 1% diario.');
  }
  if (config.paymentReminderTimezone !== 'America/Santo_Domingo') {
    throw new Error('PAYMENT_REMINDER_TIMEZONE debe ser America/Santo_Domingo.');
  }
  if (
    !Number.isInteger(config.paymentReminderWindowStartHour) ||
    !Number.isInteger(config.paymentReminderWindowEndHour) ||
    config.paymentReminderWindowStartHour < 0 ||
    config.paymentReminderWindowEndHour > 24 ||
    config.paymentReminderWindowStartHour >= config.paymentReminderWindowEndHour
  ) {
    throw new Error('PAYMENT_REMINDER_WINDOW_START_HOUR/END_HOUR deben definir una ventana valida.');
  }
  const allowedDays = config.paymentReminderAllowedDays
    .split(',')
    .map((value) => Number(value.trim()))
    .filter((value) => Number.isInteger(value));
  if (allowedDays.length === 0 || allowedDays.some((value) => value < 0 || value > 6)) {
    throw new Error('PAYMENT_REMINDER_ALLOWED_DAYS debe usar numeros 0-6.');
  }
  if (config.paymentReminderStartDate && !/^\d{4}-\d{2}-\d{2}$/.test(config.paymentReminderStartDate)) {
    throw new Error('PAYMENT_REMINDER_START_DATE debe tener formato YYYY-MM-DD.');
  }
  const testNumbers = config.paymentRemindersTestNumbers
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  if (config.paymentRemindersTestMode && testNumbers.length === 0) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS no puede estar vacio en modo prueba.');
  }
  if (testNumbers.some((value) => !/^\d{11}$/.test(value))) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS solo acepta numeros normalizados de 11 digitos.');
  }
  if (new Set(testNumbers).size !== testNumbers.length) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS no puede contener duplicados.');
  }
  if (config.paymentRemindersTestMode && config.paymentRemindersAllowRealRecipients) {
    throw new Error('No combine PAYMENT_REMINDERS_TEST_MODE=true con PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS=true.');
  }
  if (config.paymentRemindersEnabled && !config.paymentRemindersDryRun) {
    if (!config.whatsappAccessToken.trim()) missing.push('WHATSAPP_ACCESS_TOKEN');
    if (!config.whatsappPhoneNumberId.trim()) missing.push('WHATSAPP_PHONE_NUMBER_ID');
  }
  if (missing.length > 0) {
    throw new Error(`Variables requeridas invalidas: ${missing.join(', ')}`);
  }
  if (config.paymentRemindersTestMode) {
    console.warn('PAYMENT REMINDERS RUNNING IN TEST MODE');
    console.warn('REAL CUSTOMER RECIPIENTS ARE BLOCKED');
  }
}
