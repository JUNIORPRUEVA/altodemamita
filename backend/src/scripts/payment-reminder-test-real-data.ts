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
  ELEGANT1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ELEGANT2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ELEGANT3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ELEGANT4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ELEGANT5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROFESSIONAL1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROFESSIONAL2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROFESSIONAL3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROFESSIONAL4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROFESSIONAL5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROJECT_PAYMENT_REMINDER_TEMPLATE,
  buildElegantInstallmentParameters,
  buildInstallmentDetail,
  buildInstallmentDetailLines,
  formatCurrency,
  resolveDetailedTemplateName,
} from '../services/paymentReminder.service';
import { WhatsappService } from '../services/whatsapp.service';

const DEFAULT_ALLOWED_RECIPIENT = '18295319442';
const ONLY_ALLOWED_RECIPIENT = normalizeTestNumbers([process.env.PAYMENT_REMINDER_TEST_REAL_DATA_RECIPIENT ?? DEFAULT_ALLOWED_RECIPIENT])[0];
const SAMPLE_COUNT = Number(process.env.PAYMENT_REMINDER_TEST_REAL_DATA_COUNT ?? '1');
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
  const approvedTemplates = await findApprovedTemplates();

  const salesData = await findOverdueSales(SAMPLE_COUNT, approvedTemplates);
  if (salesData.length < SAMPLE_COUNT) {
    throw new Error(`Solo se encontraron ${salesData.length} ventas vencidas validas para esta prueba.`);
  }

  const deliveries = [];
  for (const saleData of salesData) {
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
      throw new Error(`Destinatario final invalido. La prueba solo puede enviarse a ${ONLY_ALLOWED_RECIPIENT}.`);
    }

    const templateName = resolveDetailedTemplateName(
      config.whatsappPaymentTestTemplate,
      saleData.summary.cantidadCuotasVencidas,
    );
    const template = approvedTemplates.get(templateName);
    if (!template) {
      throw new Error(`La plantilla ${templateName} no esta aprobada para esta venta.`);
    }
    const payloadParameters = buildTemplateVariables(saleData, templateName);

    const preview = {
      companyId: saleData.sale.companyId,
      saleSyncId: saleData.sale.syncId,
      customerName: saleData.client.name,
      originalRecipientMasked: maskPhone(saleData.client.phone),
      solar: saleData.lotLabel,
      overdueInstallments: saleData.summary.cantidadCuotasVencidas,
      principalPending: formatCurrency(saleData.summary.capitalPendiente),
      lateFee: formatCurrency(saleData.summary.moraTotal),
      total: formatCurrency(saleData.summary.totalGeneral),
      lastOverdueInstallment: saleData.summary.ultimaCuotaVencidaSyncId,
      finalTestRecipient: ONLY_ALLOWED_RECIPIENT,
    };

    const notification = await reserveTestNotification(saleData, payloadParameters, templateName);
    const delivery = await reserveTestDelivery(notification.id, preview.originalRecipientMasked);

    const service = new WhatsappService();
    try {
      const result = await service.sendTemplateMessage({
        to: ONLY_ALLOWED_RECIPIENT,
        templateName,
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

      deliveries.push({
        success: true,
        sale: preview,
        delivery: {
          actualRecipient: ONLY_ALLOWED_RECIPIENT,
          template: template.name,
          httpStatus: result.httpStatus,
          acceptedByMeta: true,
          whatsappMessageId: result.messageId,
          status: 'ACCEPTED',
        },
        payload: redactedPayload(payloadParameters, templateName),
        webhookStatus: await findRecentWebhookStatus(result.messageId),
      });
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
      deliveries.push({
        success: false,
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
        payload: redactedPayload(payloadParameters, templateName),
        webhookStatus: null,
      });
      process.exitCode = 1;
    }
  }

  console.log(JSON.stringify({
    success: deliveries.every((item) => item.success),
    mode: 'TEST_REAL_DATA',
    templateBase: config.whatsappPaymentTestTemplate,
    deliveryStatusNote: 'HTTP 200/ACCEPTED no significa DELIVERED. La entrega final se confirma por webhook.',
    deliveries,
  }, null, 2));
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
  if (!ONLY_ALLOWED_RECIPIENT || numbers.length !== 1 || numbers[0] !== ONLY_ALLOWED_RECIPIENT) {
    throw new Error(`PAYMENT_REMINDERS_TEST_NUMBERS debe contener unicamente ${ONLY_ALLOWED_RECIPIENT}.`);
  }
}

async function findOverdueSales(count: number, approvedTemplates: Map<string, TemplateRecord>) {
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
  const salesData = [];

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
      const templateName = resolveDetailedTemplateName(
        config.whatsappPaymentTestTemplate,
        summary.cantidadCuotasVencidas,
      );
      if (!approvedTemplates.has(templateName)) continue;
      salesData.push({
        sale,
        client,
        lot,
        lotLabel: lot ? lotDisplay(lot) : 'No especificado',
        summary,
      });
      if (salesData.length >= count) return salesData;
    }
  }
  return salesData;
}

function buildTemplateVariables(input: {
  client: { name: string };
  sale: { syncId: string };
  lotLabel: string;
  summary: LateFeeSummary;
}, templateName = config.whatsappPaymentTestTemplate) {
  if (templateName === PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      String(input.summary.cantidadCuotasVencidas),
      formatCurrency(input.summary.capitalPendiente),
      formatCurrency(input.summary.moraTotal),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (templateName === DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      buildInstallmentDetail(input.summary),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (templateName === DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      ...buildInstallmentDetailLines(input.summary, 3),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (templateName === DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      input.lotLabel,
      ...buildInstallmentDetailLines(input.summary, 5),
      formatCurrency(input.summary.totalGeneral),
    ];
  }
  if (isSeparatedInstallmentTemplate(templateName)) {
    const capacity = Number(templateName.match(/(\d)$/)?.[1] ?? input.summary.cuotas.length);
    return [
      input.lotLabel,
      ...buildElegantInstallmentParameters(input.summary, capacity),
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

function isSeparatedInstallmentTemplate(templateName: string) {
  return [
    ELEGANT1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    ELEGANT2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    ELEGANT3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    ELEGANT4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    ELEGANT5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    PROFESSIONAL1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    PROFESSIONAL2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    PROFESSIONAL3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    PROFESSIONAL4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    PROFESSIONAL5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ].includes(templateName);
}

function shortContractId(value: string) {
  return value.slice(-5);
}

type OverdueSaleData = Awaited<ReturnType<typeof findOverdueSales>>[number];

async function reserveTestNotification(input: OverdueSaleData, payload: string[], templateName: string) {
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
      templateName,
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

async function findApprovedTemplates() {
  const body = await graphGet(
    `${config.whatsappBusinessAccountId}/message_templates?fields=name,status,language,category&limit=100`,
  ) as { data?: TemplateRecord[] };
  const approved = new Map<string, TemplateRecord>();
  for (const item of body.data ?? []) {
    if (item.language === LANGUAGE_CODE && ['ACTIVE', 'APPROVED'].includes(item.status)) {
      approved.set(item.name, item);
    }
  }
  const baseTemplate = approved.get(config.whatsappPaymentTestTemplate);
  const baseLooksLikeFamily = /\d$/.test(config.whatsappPaymentTestTemplate);
  if (!baseTemplate && !baseLooksLikeFamily) {
    throw new Error(`La plantilla ${config.whatsappPaymentTestTemplate} con idioma ${LANGUAGE_CODE} no aparece aprobada en Meta.`);
  }
  return approved;
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

function redactedPayload(parameters: string[], templateName: string) {
  return {
    messaging_product: 'whatsapp',
    to: ONLY_ALLOWED_RECIPIENT,
    type: 'template',
    template: {
      name: templateName,
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
