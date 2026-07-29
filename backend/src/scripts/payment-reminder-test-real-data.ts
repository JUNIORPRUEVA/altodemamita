import { config } from '../config';
import { prisma } from '../prisma';
import {
  LateFeeCalculationService,
  LateFeeSummary,
} from '../services/lateFeeCalculation.service';
import {
  maskPhone,
  normalizeTestNumbers,
  resolvePaymentReminderRecipients,
} from '../services/paymentReminderRecipients.service';
import {
  DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROJECT_PAYMENT_REMINDER_TEMPLATE,
  buildInstallmentDetail,
  buildInstallmentDetailLines,
  formatCurrency,
} from '../services/paymentReminder.service';
import { WhatsappService } from '../services/whatsapp.service';

const ONLY_ALLOWED_RECIPIENT = '18295319442';
const TEST_NOTIFICATION_TYPE = 'OVERDUE_INSTALLMENTS_TEST_REAL_DATA';
const TEST_RUN_TYPE = `${TEST_NOTIFICATION_TYPE}_${new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14)}`;
const LANGUAGE_CODE = 'es';

type TemplateRecord = {
  name: string;
  status: string;
  language: string;
};

async function main() {
  validateSafetyConfig();
  const phoneNumber = await getPhoneNumberStatus();
  if (phoneNumber.status !== 'CONNECTED') {
    throw new Error(`El numero emisor no esta CONNECTED. Estado actual: ${phoneNumber.status ?? 'desconocido'}`);
  }
  const template = await findApprovedTemplate();

  const saleData = await findOneOverdueSale();
  if (!saleData) {
    throw new Error('No existe una venta vencida valida para esta prueba.');
  }

  const recipients = resolvePaymentReminderRecipients({
    customerPhone: saleData.client.phone,
    testMode: true,
    allowRealRecipients: false,
    testNumbers: [ONLY_ALLOWED_RECIPIENT],
  });
  if (
    recipients.mode !== 'TEST' ||
    recipients.recipients.length !== 1 ||
    recipients.recipients[0] !== ONLY_ALLOWED_RECIPIENT
  ) {
    throw new Error('Destinatario final invalido. La prueba solo puede enviarse a 18295319442.');
  }

  const payloadParameters = buildTemplateVariables(saleData);

  const preview = {
    companyId: saleData.sale.companyId,
    saleSyncId: saleData.sale.syncId,
    customerName: saleData.client.name,
    originalRecipientMasked: maskPhone(saleData.client.phone),
    solar: saleData.lotLabel,
    contract: shortContractId(saleData.sale.syncId),
    overdueInstallments: saleData.summary.cantidadCuotasVencidas,
    principalPending: formatCurrency(saleData.summary.capitalPendiente),
    lateFee: formatCurrency(saleData.summary.moraTotal),
    total: formatCurrency(saleData.summary.totalGeneral),
    lastOverdueInstallment: saleData.summary.ultimaCuotaVencidaSyncId,
    finalTestRecipient: ONLY_ALLOWED_RECIPIENT,
  };
  console.log(JSON.stringify({ preview }, null, 2));

  const notification = await reserveTestNotification(saleData, payloadParameters);
  const delivery = await reserveTestDelivery(notification.id, preview.originalRecipientMasked);

  const service = new WhatsappService();
  try {
    const result = await service.sendTemplateMessage({
      to: ONLY_ALLOWED_RECIPIENT,
      templateName: config.whatsappPaymentTestTemplate,
      languageCode: LANGUAGE_CODE,
      parameters: payloadParameters,
    });
    await prisma.paymentReminderDelivery.update({
      where: { id: delivery.id },
      data: {
        status: 'ACCEPTED',
        attempts: { increment: 1 },
        whatsappMessageId: result.messageId,
        sentAt: new Date(),
        error: null,
      },
    });
    await prisma.paymentReminderNotification.update({
      where: { id: notification.id },
      data: {
        status: 'ACCEPTED',
        attempts: { increment: 1 },
        whatsappMessageId: result.messageId,
        sentAt: new Date(),
        error: null,
      },
    });

    console.log(JSON.stringify({
      success: true,
      mode: 'TEST_REAL_DATA',
      sale: preview,
      delivery: {
        actualRecipient: ONLY_ALLOWED_RECIPIENT,
        template: template.name,
        httpStatus: result.httpStatus,
        acceptedByMeta: true,
        whatsappMessageId: result.messageId,
        status: 'ACCEPTED',
      },
      payload: redactedPayload(payloadParameters),
      webhookStatus: await findRecentWebhookStatus(result.messageId),
    }, null, 2));
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Error desconocido';
    await prisma.paymentReminderDelivery.update({
      where: { id: delivery.id },
      data: {
        status: 'FAILED',
        attempts: { increment: 1 },
        error: message.slice(0, 500),
      },
    });
    await prisma.paymentReminderNotification.update({
      where: { id: notification.id },
      data: {
        status: 'FAILED',
        attempts: { increment: 1 },
        error: message.slice(0, 500),
      },
    });
    console.log(JSON.stringify({
      success: false,
      mode: 'TEST_REAL_DATA',
      sale: preview,
      delivery: {
        actualRecipient: ONLY_ALLOWED_RECIPIENT,
        template: template.name,
        httpStatus: parseHttpStatus(error),
        acceptedByMeta: false,
        whatsappMessageId: null,
        status: 'FAILED',
        error: message,
      },
      payload: redactedPayload(payloadParameters),
      webhookStatus: null,
    }, null, 2));
    process.exitCode = 1;
  }
}

function validateSafetyConfig() {
  if (config.paymentRemindersEnabled) {
    throw new Error('PAYMENT_REMINDERS_ENABLED debe estar en false. No se ejecuta cron en esta prueba.');
  }
  if (config.paymentRemindersDryRun) {
    throw new Error('PAYMENT_REMINDERS_DRY_RUN debe estar en false para enviar la plantilla.');
  }
  if (!config.paymentRemindersTestMode) {
    throw new Error('PAYMENT_REMINDERS_TEST_MODE debe estar en true.');
  }
  if (config.paymentRemindersAllowRealRecipients) {
    throw new Error('PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS debe estar en false.');
  }
  if (Number(config.lateFeeDailyRate) !== 0.01) {
    throw new Error('LATE_FEE_DAILY_RATE debe ser 0.01.');
  }
  if (!config.whatsappPaymentTestTemplate.trim()) {
    throw new Error('WHATSAPP_PAYMENT_TEST_TEMPLATE es requerido.');
  }
  if (config.whatsappTemplateLanguage !== LANGUAGE_CODE) {
    throw new Error(`WHATSAPP_TEMPLATE_LANGUAGE debe ser ${LANGUAGE_CODE}.`);
  }
  if (config.whatsappPhoneNumberId !== '1284301628092919') {
    throw new Error('WHATSAPP_PHONE_NUMBER_ID debe ser 1284301628092919.');
  }
  if (config.whatsappBusinessAccountId !== '991472327202360') {
    throw new Error('WHATSAPP_BUSINESS_ACCOUNT_ID debe ser 991472327202360.');
  }
  if (!config.whatsappAccessToken.trim()) {
    throw new Error('WHATSAPP_ACCESS_TOKEN es requerido.');
  }
  const numbers = normalizeTestNumbers(
    config.paymentRemindersTestNumbers.split(',').map((value) => value.trim()).filter(Boolean),
  );
  if (numbers.length !== 1 || numbers[0] !== ONLY_ALLOWED_RECIPIENT) {
    throw new Error('PAYMENT_REMINDERS_TEST_NUMBERS debe contener unicamente 18295319442.');
  }
}

async function findOneOverdueSale() {
  const calculator = new LateFeeCalculationService({
    dailyRate: config.lateFeeDailyRate,
    timezone: config.paymentReminderTimezone,
  });
  const candidateInstallments = await prisma.installment.findMany({
    where: {
      companyId: config.companyTenantKey ? undefined : undefined,
      deletedAt: null,
      dueDate: { lt: new Date() },
      saleSyncId: { not: null },
      status: { notIn: ['pagada', 'cancelada', 'ajustada'] },
    },
    orderBy: [{ dueDate: 'desc' }, { updatedAt: 'desc' }],
    take: 200,
  });
  const saleSyncIds = [...new Set(candidateInstallments.map((item) => item.saleSyncId).filter((value): value is string => Boolean(value)))];

  for (const saleSyncId of saleSyncIds) {
    const sale = await prisma.sale.findFirst({
      where: {
        syncId: saleSyncId,
        deletedAt: null,
        status: { notIn: ['pagada', 'cancelada', 'anulada', 'cerrada', 'saldada'] },
      },
      orderBy: { updatedAt: 'desc' },
    });
    if (!sale || !sale.clientSyncId) continue;

    const client = await prisma.client.findFirst({
      where: { companyId: sale.companyId, syncId: sale.clientSyncId, deletedAt: null },
    });
    if (!client) continue;

    const [lot, installments, payments] = await Promise.all([
      sale.lotSyncId
        ? prisma.lot.findFirst({ where: { companyId: sale.companyId, syncId: sale.lotSyncId, deletedAt: null } })
        : null,
      prisma.installment.findMany({
        where: { companyId: sale.companyId, saleSyncId: sale.syncId, deletedAt: null },
        orderBy: [{ dueDate: 'asc' }, { installmentNumber: 'asc' }],
      }),
      prisma.payment.findMany({
        where: { companyId: sale.companyId, saleSyncId: sale.syncId, deletedAt: null },
        orderBy: { paidAt: 'asc' },
      }),
    ]);

    const summary = calculator.calculateSaleSummary({
      context: {
        companyId: sale.companyId,
        clienteId: client.id,
        clientSyncId: sale.clientSyncId,
        clienteNombre: client.name,
        clienteTelefono: client.phone,
        ventaId: sale.id,
        saleSyncId: sale.syncId,
        lotLabel: lot ? lotDisplay(lot) : null,
      },
      installments,
      payments,
    });
    if (
      summary.cantidadCuotasVencidas > 0 &&
      Number(summary.capitalPendiente) > 0 &&
      Number(summary.moraTotal) >= 0 &&
      Number(summary.totalGeneral) >= 0
    ) {
      return {
        sale,
        client,
        lot,
        lotLabel: lot ? lotDisplay(lot) : 'No especificado',
        summary,
      };
    }
  }
  return null;
}

function buildTemplateVariables(input: {
  client: { name: string };
  sale: { syncId: string };
  lotLabel: string;
  summary: LateFeeSummary;
}) {
  if (config.whatsappPaymentTestTemplate === PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      String(input.summary.cantidadCuotasVencidas),
      formatCurrency(input.summary.capitalPendiente),
      formatCurrency(input.summary.moraTotal),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (config.whatsappPaymentTestTemplate === DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      buildInstallmentDetail(input.summary),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (config.whatsappPaymentTestTemplate === DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      ...buildInstallmentDetailLines(input.summary, 3),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (config.whatsappPaymentTestTemplate === DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      ...buildInstallmentDetailLines(input.summary, 5),
      formatCurrency(input.summary.totalGeneral),
    ];
  }

  return [
    input.client.name,
    String(input.summary.cantidadCuotasVencidas),
    input.lotLabel,
    shortContractId(input.sale.syncId),
    formatCurrency(input.summary.capitalPendiente),
    formatCurrency(input.summary.moraTotal),
    formatCurrency(input.summary.totalGeneral),
  ];
}

function shortContractId(value: string) {
  return value.slice(-5);
}

async function reserveTestNotification(input: Awaited<ReturnType<typeof findOneOverdueSale>> extends infer T ? NonNullable<T> : never, payload: string[]) {
  const lastOverdueInstallmentSyncId = input.summary.ultimaCuotaVencidaSyncId;
  if (!lastOverdueInstallmentSyncId) {
    throw new Error('No hay ultima cuota vencida para registrar la prueba.');
  }
  return prisma.paymentReminderNotification.create({
    data: {
      companyId: input.sale.companyId,
      clientSyncId: input.sale.clientSyncId,
      saleSyncId: input.sale.syncId,
      type: TEST_RUN_TYPE,
      period: input.summary.periodoNotificacion,
      lastOverdueInstallmentSyncId,
      overdueInstallmentCount: input.summary.cantidadCuotasVencidas,
      pendingPrincipal: input.summary.capitalPendiente,
      lateFeeTotal: input.summary.moraTotal,
      totalDue: input.summary.totalGeneral,
      destinationPhone: ONLY_ALLOWED_RECIPIENT,
      templateName: config.whatsappPaymentTestTemplate,
      status: 'PROCESSING',
      scheduledAt: new Date(),
      payload,
      testMode: true,
      redirected: true,
      originalRecipientMasked: maskPhone(input.client.phone),
    },
  });
}

async function reserveTestDelivery(notificationId: string, originalRecipientMasked: string | null) {
  return prisma.paymentReminderDelivery.create({
    data: {
      notificationId,
      actualRecipient: ONLY_ALLOWED_RECIPIENT,
      originalRecipientMasked,
      testMode: true,
      redirected: true,
      status: 'PROCESSING',
    },
  });
}

async function getPhoneNumberStatus() {
  return graphGet(
    `${config.whatsappPhoneNumberId}?fields=id,display_phone_number,verified_name,quality_rating,platform_type,code_verification_status,name_status,new_name_status,status`,
  ) as Promise<any>;
}

async function findApprovedTemplate() {
  const body = await graphGet(
    `${config.whatsappBusinessAccountId}/message_templates?fields=name,status,language,category&limit=100`,
  ) as { data?: TemplateRecord[] };
  const template = (body.data ?? []).find((item) =>
    item.name === config.whatsappPaymentTestTemplate &&
    item.language === LANGUAGE_CODE,
  );
  if (!template) {
    throw new Error(`La plantilla ${config.whatsappPaymentTestTemplate} con idioma ${LANGUAGE_CODE} no aparece en Meta.`);
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

async function findRecentWebhookStatus(messageId: string) {
  const delivery = await prisma.paymentReminderDelivery.findFirst({
    where: { whatsappMessageId: messageId },
    select: {
      status: true,
      error: true,
      sentAt: true,
      deliveredAt: true,
      readAt: true,
    },
  });
  if (!delivery || delivery.status === 'ACCEPTED') {
    return {
      status: 'ACCEPTED_ONLY',
      note: 'No hay evento webhook SENT, DELIVERED, READ o FAILED disponible aun.',
    };
  }
  return delivery;
}

function redactedPayload(parameters: string[]) {
  return {
    messaging_product: 'whatsapp',
    to: ONLY_ALLOWED_RECIPIENT,
    type: 'template',
    template: {
      name: config.whatsappPaymentTestTemplate,
      language: { code: LANGUAGE_CODE },
      components: [
        {
          type: 'body',
          parameters: parameters.map((text, index) => ({
            type: 'text',
            text: index === 0 ? text : text,
          })),
        },
      ],
    },
  };
}

function lotDisplay(lot: { block: string | null; number: string | null }) {
  const block = lot.block?.trim() ?? '';
  const number = lot.number?.trim() ?? '';
  if (block && number) return `M${block}-S${number}`;
  if (number) return `Solar ${number}`;
  if (block) return `Manzana ${block}`;
  return 'No especificado';
}

function parseHttpStatus(error: unknown) {
  const match = error instanceof Error ? error.message.match(/WhatsApp API error (\d+)/) : null;
  return match ? Number(match[1]) : null;
}

function safeMetaError(body: unknown) {
  const message = (body as any)?.error?.message;
  return typeof message === 'string' ? message.slice(0, 240) : 'respuesta invalida';
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
