import { config } from '../config';
import { normalizeTestNumbers } from '../services/paymentReminderRecipients.service';
import {
  DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROJECT_PAYMENT_REMINDER_TEMPLATE,
} from '../services/paymentReminder.service';
import { WhatsappService } from '../services/whatsapp.service';

const AUTHORIZED_TEST_NUMBERS = ['18295344286', '18295319442'];
const LEGACY_TEST_PARAMETERS = ['Juan Perez', '2', 'Solar 28', 'V-000145', 'RD$20,000.00', 'RD$9,200.00', 'RD$29,200.00'];
const PROJECT_TEST_PARAMETERS = ['Solar 28', '2', 'RD$20,000.00', 'RD$6,000.00', 'RD$26,000.00'];
const DETAILED_PROJECT_TEST_PARAMETERS = [
  'Solar 28',
  'Cuota mes de junio 2026: RD$25,000.00 mas mora: RD$7,500.00\n\nCuota mes de julio 2026: RD$25,000.00 mas mora: RD$7,500.00\n\nCuota mes de agosto 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'RD$97,500.00',
];
const DETAILED3_PROJECT_TEST_PARAMETERS = [
  'Solar 28',
  'Cuota mes de junio 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de julio 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de agosto 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'RD$97,500.00',
];
const DETAILED5_PROJECT_TEST_PARAMETERS = [
  'Solar 28',
  'Cuota mes de abril 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de mayo 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de junio 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de julio 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'Cuota mes de agosto 2026: RD$25,000.00 mas mora: RD$7,500.00',
  'RD$162,500.00',
];

type TemplateRecord = {
  name: string;
  status: string;
  language: string;
};

async function main() {
  validateLocalSafetyConfig();

  const phoneNumber = await getPhoneNumberStatus();
  if (phoneNumber.status !== 'CONNECTED') {
    throw new Error(`El numero emisor no esta CONNECTED. Estado actual: ${phoneNumber.status ?? 'desconocido'}`);
  }

  const template = await findApprovedTemplate(config.whatsappBusinessAccountId);
  const numbers = resolveAuthorizedRecipients();
  const service = new WhatsappService();
  const parameters = config.whatsappPaymentTestTemplate === DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE
    ? DETAILED5_PROJECT_TEST_PARAMETERS
    : config.whatsappPaymentTestTemplate === DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE
      ? DETAILED3_PROJECT_TEST_PARAMETERS
      : config.whatsappPaymentTestTemplate === DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE
      ? DETAILED_PROJECT_TEST_PARAMETERS
      : config.whatsappPaymentTestTemplate === PROJECT_PAYMENT_REMINDER_TEMPLATE
      ? PROJECT_TEST_PARAMETERS
      : LEGACY_TEST_PARAMETERS;

  const recipients = [];
  for (const to of numbers) {
    try {
      const result = await service.sendTemplateMessage({
        to,
        templateName: config.whatsappPaymentTestTemplate,
        languageCode: config.whatsappTemplateLanguage,
        parameters,
      });
      recipients.push({
        phone: to,
        httpStatus: result.httpStatus,
        acceptedByMeta: true,
        whatsappMessageId: result.messageId,
        templateName: config.whatsappPaymentTestTemplate,
        languageCode: config.whatsappTemplateLanguage,
        status: 'ACCEPTED',
      });
    } catch (error) {
      recipients.push({
        phone: to,
        httpStatus: parseHttpStatus(error),
        acceptedByMeta: false,
        whatsappMessageId: null,
        templateName: config.whatsappPaymentTestTemplate,
        languageCode: config.whatsappTemplateLanguage,
        status: 'FAILED',
        error: error instanceof Error ? error.message : 'Error desconocido',
      });
    }
  }

  console.log(JSON.stringify({
    success: recipients.every((item) => item.acceptedByMeta),
    mode: 'TEST',
    sender: {
      phoneNumberId: config.whatsappPhoneNumberId,
      displayPhoneNumber: phoneNumber.display_phone_number,
      status: phoneNumber.status,
    },
    template: template.name,
    templateStatus: template.status,
    languageCode: template.language,
    recipients,
    deliveryStatusNote: 'HTTP 200/ACCEPTED no significa DELIVERED. La entrega final se confirma por webhook.',
  }, null, 2));
}

function validateLocalSafetyConfig() {
  if (config.paymentRemindersEnabled) {
    throw new Error('PAYMENT_REMINDERS_ENABLED debe estar en false para esta prueba manual.');
  }
  if (config.paymentRemindersDryRun) {
    throw new Error('PAYMENT_REMINDERS_DRY_RUN debe estar en false para llamar a WhatsApp.');
  }
  if (!config.paymentRemindersTestMode) {
    throw new Error('PAYMENT_REMINDERS_TEST_MODE debe estar activo para esta prueba.');
  }
  if (config.paymentRemindersAllowRealRecipients) {
    throw new Error('PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS debe estar en false para esta prueba.');
  }
  if (!config.whatsappAccessToken.trim()) {
    throw new Error('WHATSAPP_ACCESS_TOKEN es requerido.');
  }
  if (!config.whatsappPhoneNumberId.trim()) {
    throw new Error('WHATSAPP_PHONE_NUMBER_ID es requerido.');
  }
  if (!config.whatsappBusinessAccountId.trim()) {
    throw new Error('WHATSAPP_BUSINESS_ACCOUNT_ID es requerido.');
  }
  if (!config.whatsappPaymentTestTemplate.trim()) {
    throw new Error('WHATSAPP_PAYMENT_TEST_TEMPLATE es requerido.');
  }
  if (config.whatsappTemplateLanguage !== 'es') {
    throw new Error('WHATSAPP_TEMPLATE_LANGUAGE debe ser es.');
  }
}

function resolveAuthorizedRecipients() {
  const numbers = normalizeTestNumbers(
    config.paymentRemindersTestNumbers.split(',').map((value) => value.trim()).filter(Boolean),
  );
  if (
    numbers.length !== AUTHORIZED_TEST_NUMBERS.length ||
    numbers.some((number, index) => number !== AUTHORIZED_TEST_NUMBERS[index])
  ) {
    throw new Error(`Destinatarios no autorizados. Deben ser exactamente: ${AUTHORIZED_TEST_NUMBERS.join(',')}`);
  }
  return numbers;
}

async function getPhoneNumberStatus() {
  const body = await graphGet(
    `${config.whatsappPhoneNumberId}?fields=id,display_phone_number,verified_name,quality_rating,platform_type,code_verification_status,name_status,new_name_status,status`,
  );
  return body as any;
}

async function findApprovedTemplate(wabaId?: string) {
  if (!wabaId) {
    throw new Error('No se pudo obtener el WABA ID desde WHATSAPP_PHONE_NUMBER_ID.');
  }
  const body = await graphGet(
    `${wabaId}/message_templates?fields=name,status,language,category&limit=100`,
  ) as { data?: TemplateRecord[] };
  const template = (body.data ?? []).find((item) =>
    item.name === config.whatsappPaymentTestTemplate &&
    item.language === config.whatsappTemplateLanguage,
  );
  if (!template) {
    throw new Error(`La plantilla ${config.whatsappPaymentTestTemplate} con idioma ${config.whatsappTemplateLanguage} no aparece en Meta.`);
  }
  if (!['ACTIVE', 'APPROVED'].includes(template.status)) {
    throw new Error(`La plantilla existe pero no esta activa. Estado actual: ${template.status}`);
  }
  return template;
}

async function graphGet(path: string) {
  const response = await fetch(`https://graph.facebook.com/v20.0/${path}`, {
    headers: {
      Authorization: `Bearer ${config.whatsappAccessToken}`,
    },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Meta API error ${response.status}: ${safeMetaError(body)}`);
  }
  return body;
}

function parseHttpStatus(error: unknown) {
  const match = error instanceof Error ? error.message.match(/WhatsApp API error (\d+)/) : null;
  return match ? Number(match[1]) : null;
}

function safeMetaError(body: unknown) {
  const message = (body as any)?.error?.message;
  return typeof message === 'string' ? message.slice(0, 240) : 'respuesta invalida';
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
