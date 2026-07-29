import { Prisma } from '@prisma/client';
import { config } from '../config';
import { prisma } from '../prisma';
import {
  LateFeeCalculationService,
  LateFeeSummary,
  PAYMENT_REMINDER_TYPE,
} from './lateFeeCalculation.service';
import {
  PaymentReminderRecipients,
  resolvePaymentReminderRecipients,
} from './paymentReminderRecipients.service';
import {
  isPaymentReminderSendWindowOpen,
  paymentReminderWindowDescription,
} from './paymentReminderWindow.service';
import { WhatsappService } from './whatsapp.service';

const TERMINAL_SALE_STATUSES = new Set(['pagada', 'cancelada', 'anulada', 'cerrada', 'saldada']);
export const PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_proyecto';
export const DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle';
export const DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle1';
export const DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle2';
export const DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle3';
export const DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle4';
export const DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE = 'recordatorio_cuotas_vencidas_detalle5';

export class PaymentReminderService {
  private readonly calculator = new LateFeeCalculationService({
    dailyRate: config.lateFeeDailyRate,
    timezone: config.paymentReminderTimezone,
  });
  private readonly whatsapp = new WhatsappService();
  private readonly approvedTemplateCache = new Map<string, boolean>();

  async getSaleSummary(companyId: string, saleSyncId: string, calculationDate = new Date()) {
    const sale = await prisma.sale.findFirst({
      where: { companyId, syncId: saleSyncId, deletedAt: null },
    });
    if (!sale || isTerminalSaleStatus(sale.status)) return null;

    const [client, lot, installments, payments, lastNotification] = await Promise.all([
      sale.clientSyncId
        ? prisma.client.findFirst({ where: { companyId, syncId: sale.clientSyncId, deletedAt: null } })
        : null,
      sale.lotSyncId
        ? prisma.lot.findFirst({ where: { companyId, syncId: sale.lotSyncId, deletedAt: null } })
        : null,
      prisma.installment.findMany({
        where: { companyId, saleSyncId, deletedAt: null },
        orderBy: [{ dueDate: 'asc' }, { installmentNumber: 'asc' }],
      }),
      prisma.payment.findMany({
        where: { companyId, saleSyncId, deletedAt: null },
        orderBy: { paidAt: 'asc' },
      }),
      prisma.paymentReminderNotification.findFirst({
        where: { companyId, saleSyncId, type: PAYMENT_REMINDER_TYPE },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    const summary = this.calculator.calculateSaleSummary({
      context: {
        companyId,
        clienteId: client?.id ?? null,
        clientSyncId: sale.clientSyncId,
        clienteNombre: client?.name ?? null,
        clienteTelefono: client?.phone ?? null,
        ventaId: sale.id,
        saleSyncId,
        lotLabel: lot ? lotDisplay(lot) : null,
      },
      installments,
      payments,
      calculationDate,
    });

    return {
      sale,
      client,
      lot,
      summary,
      lastNotification,
    };
  }

  async sendSaleReminder(input: {
    companyId: string;
    saleSyncId: string;
    calculationDate?: Date;
    force?: boolean;
    dryRun?: boolean;
    forceTestMode?: boolean;
  }) {
    if (!isPaymentReminderSendWindowOpen(input.calculationDate ?? new Date())) {
      return {
        status: 'SKIPPED_OUTSIDE_WINDOW',
        summary: null,
        window: paymentReminderWindowDescription(),
      };
    }

    const result = await this.getSaleSummary(input.companyId, input.saleSyncId, input.calculationDate);
    if (!result || result.summary.cantidadCuotasVencidas === 0 || !result.summary.ultimaCuotaVencidaSyncId) {
      return { status: 'SKIPPED_NO_OVERDUE', summary: result?.summary ?? null };
    }

    const dryRun = input.dryRun ?? config.paymentRemindersDryRun;
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: result.client?.phone,
      testMode: input.forceTestMode || config.paymentRemindersTestMode,
      allowRealRecipients: config.paymentRemindersAllowRealRecipients,
      testNumbers: parseTestNumbers(),
    });
    if (recipients.mode === 'BLOCKED') {
      logEvent('notification_skipped_no_phone', {
        companyId: input.companyId,
        saleSyncId: input.saleSyncId,
        reason: recipients.reason,
      });
      return { status: 'BLOCKED_CONFIGURATION', summary: result.summary, recipients };
    }

    const baseTemplateName = recipients.mode === 'TEST'
      ? config.whatsappPaymentTestTemplate
      : config.whatsappPaymentTemplate;
    const templateName = resolveDetailedTemplateName(baseTemplateName, result.summary.cantidadCuotasVencidas);
    const templateCapacity = getTemplateInstallmentCapacity(templateName);
    if (templateCapacity && result.summary.cantidadCuotasVencidas > templateCapacity) {
      logEvent('notification_skipped_template_capacity_exceeded', {
        companyId: input.companyId,
        saleSyncId: input.saleSyncId,
        templateName,
        overdueInstallments: result.summary.cantidadCuotasVencidas,
        templateCapacity,
      });
      return { status: 'SKIPPED_TEMPLATE_CAPACITY', summary: result.summary };
    }
    if (!dryRun && !(await this.isTemplateApproved(templateName))) {
      logEvent('notification_skipped_template_not_approved', {
        companyId: input.companyId,
        saleSyncId: input.saleSyncId,
        templateName,
        overdueInstallments: result.summary.cantidadCuotasVencidas,
      });
      return { status: 'SKIPPED_TEMPLATE_NOT_APPROVED', summary: result.summary };
    }
    const payload = buildTemplatePayload(result.summary, recipients, {
      clientName: result.client?.name ?? 'cliente',
      originalPhone: result.client?.phone ?? null,
      lotLabel: result.lot ? lotDisplay(result.lot) : 'No especificado',
      saleLabel: shortContractId(result.sale.syncId),
    }, templateName);

    if (dryRun) {
      logEvent('payment_reminder_dry_run', {
        companyId: input.companyId,
        saleSyncId: input.saleSyncId,
        overdueInstallments: result.summary.cantidadCuotasVencidas,
        mode: recipients.mode,
      });
      return {
        status: 'DRY_RUN',
        success: true,
        mode: recipients.mode,
        summary: result.summary,
        originalRecipientMasked: recipients.originalRecipientMasked,
        recipients: recipients.recipients.map((phone) => ({ phone, status: 'DRY_RUN' })),
        templateName,
        payload,
      };
    }

    const reservation = await this.reserveProcessingNotification({
      summary: result.summary,
      recipients,
      templateName,
      payload,
      force: input.force ?? false,
    });
    if (reservation.status === 'DUPLICATE') {
      logEvent('notification_skipped_duplicate', {
        companyId: input.companyId,
        saleSyncId: input.saleSyncId,
      });
      return { status: 'SKIPPED_DUPLICATE', summary: result.summary };
    }

    const deliveryResults = [];
    for (const delivery of reservation.deliveries) {
      if (delivery.status === 'SENT' || delivery.status === 'DELIVERED' || delivery.status === 'READ') {
        deliveryResults.push({ phone: delivery.actualRecipient, status: delivery.status });
        continue;
      }
      try {
        const sent = await this.whatsapp.sendTemplateMessage({
          to: delivery.actualRecipient,
          templateName,
          languageCode: config.whatsappTemplateLanguage,
          parameters: payload,
        });
        await prisma.paymentReminderDelivery.update({
          where: { id: delivery.id },
          data: {
            status: 'SENT',
            whatsappMessageId: sent.messageId,
            sentAt: new Date(),
            attempts: { increment: 1 },
            error: null,
          },
        });
        deliveryResults.push({ phone: delivery.actualRecipient, status: 'SENT', whatsappMessageId: sent.messageId });
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
        deliveryResults.push({ phone: delivery.actualRecipient, status: 'FAILED', error: message });
      }
    }

    const allSent = deliveryResults.every((delivery) => ['SENT', 'DELIVERED', 'READ'].includes(delivery.status));
    const anySent = deliveryResults.some((delivery) => ['SENT', 'DELIVERED', 'READ'].includes(delivery.status));
    const finalStatus = allSent ? 'SENT' : anySent ? 'PARTIAL_FAILED' : 'FAILED';
    await prisma.paymentReminderNotification.update({
      where: { id: reservation.notificationId },
      data: {
        status: finalStatus,
        sentAt: allSent ? new Date() : undefined,
        attempts: { increment: 1 },
        error: allSent ? null : 'Una o mas entregas fallaron.',
      },
    });
    if (anySent) {
      await this.createSnapshots(result.summary, reservation.notificationId, 'NOTIFICATION_SENT');
    }
    logEvent(allSent ? 'whatsapp_message_sent' : 'whatsapp_message_failed', {
      companyId: input.companyId,
      saleSyncId: input.saleSyncId,
      mode: recipients.mode,
    });
    return {
      success: allSent,
      status: finalStatus,
      mode: recipients.mode,
      summary: result.summary,
      originalRecipientMasked: recipients.originalRecipientMasked,
      recipients: deliveryResults,
    };
  }

  async processCompany(companyId: string, calculationDate = new Date()) {
    if (!isPaymentReminderSendWindowOpen(calculationDate)) {
      const stats = {
        checkedSales: 0,
        overdueSales: 0,
        sent: 0,
        skipped: 0,
        failed: 0,
        durationMs: 0,
        skippedReason: 'OUTSIDE_WINDOW',
      };
      logEvent('payment_reminder_job_skipped_outside_window', {
        companyId,
        window: paymentReminderWindowDescription(),
      });
      return stats;
    }

    const started = Date.now();
    const sales = await prisma.sale.findMany({
      where: { companyId, deletedAt: null },
      select: { syncId: true, status: true },
    });
    let overdueSales = 0;
    let sent = 0;
    let skipped = 0;
    let failed = 0;

    for (const sale of sales) {
      if (!isPaymentReminderSendWindowOpen(new Date())) {
        logEvent('payment_reminder_company_stopped_outside_window', { companyId });
        break;
      }
      if (isTerminalSaleStatus(sale.status)) {
        skipped += 1;
        continue;
      }
      try {
        const result = await this.sendSaleReminder({
          companyId,
          saleSyncId: sale.syncId,
          calculationDate,
        });
        if (result.summary?.cantidadCuotasVencidas) overdueSales += 1;
        if (result.status === 'SENT') sent += 1;
        else if (result.status === 'FAILED') failed += 1;
        else skipped += 1;
      } catch (error) {
        failed += 1;
        logEvent('payment_reminder_sale_failed', {
          companyId,
          saleSyncId: sale.syncId,
          error: error instanceof Error ? error.message.slice(0, 200) : 'unknown',
        });
      }
    }

    const stats = {
      checkedSales: sales.length,
      overdueSales,
      sent,
      skipped,
      failed,
      durationMs: Date.now() - started,
    };
    logEvent('payment_reminder_job_completed', { companyId, ...stats });
    return stats;
  }

  async updateWhatsappStatus(input: {
    whatsappMessageId: string;
    status: string;
    error?: string | null;
  }) {
    const statusMap: Record<string, string> = {
      SENT: 'SENT',
      DELIVERED: 'DELIVERED',
      READ: 'READ',
      FAILED: 'FAILED',
    };
    const status = statusMap[input.status] ?? input.status;
    await prisma.paymentReminderNotification.updateMany({
      where: { whatsappMessageId: input.whatsappMessageId },
      data: {
        status,
        error: input.error ? input.error.slice(0, 500) : undefined,
      },
    });
    const deliveryData: any = { status };
    if (status === 'DELIVERED') deliveryData.deliveredAt = new Date();
    if (status === 'READ') deliveryData.readAt = new Date();
    if (input.error) deliveryData.error = input.error.slice(0, 500);
    await prisma.paymentReminderDelivery.updateMany({
      where: { whatsappMessageId: input.whatsappMessageId },
      data: deliveryData,
    });
  }

  private async reserveSkippedNotification(
    summary: LateFeeSummary,
    recipients: PaymentReminderRecipients,
    status: string,
  ) {
    try {
      await prisma.paymentReminderNotification.create({
        data: notificationData(summary, {
          recipients,
          templateName: config.whatsappPaymentTemplate,
          payload: {},
          status,
        }),
      });
    } catch (error) {
      if (!isUniqueConstraint(error)) throw error;
    }
  }

  private async reserveProcessingNotification(input: {
    summary: LateFeeSummary;
    recipients: PaymentReminderRecipients;
    templateName: string;
    payload: string[];
    force: boolean;
  }) {
    try {
      const notification = await prisma.paymentReminderNotification.create({
        data: notificationData(input.summary, {
          recipients: input.recipients,
          templateName: input.templateName,
          payload: input.payload,
          status: 'PROCESSING',
        }),
      });
      const deliveries = await this.ensureDeliveries(notification.id, input.recipients);
      return { status: 'RESERVED' as const, notificationId: notification.id, deliveries };
    } catch (error) {
      if (isUniqueConstraint(error) && !input.force) {
        return { status: 'DUPLICATE' as const };
      }
      if (isUniqueConstraint(error) && input.force) {
        const notification = await prisma.paymentReminderNotification.update({
          where: {
            companyId_saleSyncId_type_lastOverdueInstallmentSyncId: {
              companyId: input.summary.companyId!,
              saleSyncId: input.summary.ventaSyncId,
              type: PAYMENT_REMINDER_TYPE,
              lastOverdueInstallmentSyncId: input.summary.ultimaCuotaVencidaSyncId!,
            },
          },
          data: {
            status: 'PROCESSING',
            destinationPhone: input.recipients.recipients.join(','),
            templateName: input.templateName,
            payload: input.payload as any,
            error: null,
            scheduledAt: new Date(),
          },
        });
        const deliveries = await this.ensureDeliveries(notification.id, input.recipients);
        return { status: 'RESERVED' as const, notificationId: notification.id, deliveries };
      }
      throw error;
    }
  }

  private async ensureDeliveries(notificationId: string, recipients: PaymentReminderRecipients) {
    for (const actualRecipient of recipients.recipients) {
      await prisma.paymentReminderDelivery.upsert({
        where: {
          notificationId_actualRecipient: {
            notificationId,
            actualRecipient,
          },
        },
        create: {
          notificationId,
          actualRecipient,
          originalRecipientMasked: recipients.originalRecipientMasked,
          testMode: recipients.mode === 'TEST',
          redirected: recipients.redirected,
          status: 'PENDING',
        },
        update: {
          originalRecipientMasked: recipients.originalRecipientMasked,
          testMode: recipients.mode === 'TEST',
          redirected: recipients.redirected,
        },
      });
    }
    return prisma.paymentReminderDelivery.findMany({
      where: {
        notificationId,
        status: { in: ['PENDING', 'FAILED', 'PROCESSING'] },
      },
      orderBy: { actualRecipient: 'asc' },
    });
  }

  private async createSnapshots(summary: LateFeeSummary, notificationId: string, eventType: string) {
    if (!summary.companyId) return;
    await prisma.lateFeeSnapshot.createMany({
      data: summary.cuotas.map((cuota) => ({
        companyId: summary.companyId,
        clientSyncId: summary.clienteSyncId,
        saleSyncId: summary.ventaSyncId,
        installmentSyncId: cuota.cuotaSyncId,
        calculatedAt: new Date(`${summary.fechaCalculo}T04:00:00.000Z`),
        baseBalance: cuota.saldoPendiente,
        overdueDays: cuota.diasAtraso,
        dailyRate: cuota.tasaDiaria,
        calculatedLateFee: cuota.mora,
        eventType,
        notificationId,
      })) as any,
    });
  }

  private async isTemplateApproved(templateName: string) {
    const cached = this.approvedTemplateCache.get(templateName);
    if (cached !== undefined) return cached;
    if (!config.whatsappBusinessAccountId || !config.whatsappAccessToken) {
      this.approvedTemplateCache.set(templateName, false);
      return false;
    }
    try {
      const response = await fetch(
        `https://graph.facebook.com/v20.0/${config.whatsappBusinessAccountId}/message_templates?fields=name,status,language&limit=200`,
        {
          headers: {
            Authorization: `Bearer ${config.whatsappAccessToken}`,
          },
        },
      );
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        this.approvedTemplateCache.set(templateName, false);
        return false;
      }
      for (const item of body?.data ?? []) {
        if (item?.language === config.whatsappTemplateLanguage) {
          this.approvedTemplateCache.set(
            item.name,
            ['APPROVED', 'ACTIVE'].includes(item.status),
          );
        }
      }
      return this.approvedTemplateCache.get(templateName) ?? false;
    } catch {
      this.approvedTemplateCache.set(templateName, false);
      return false;
    }
  }
}

function shortContractId(value: string) {
  return value.slice(-5);
}

export function isTerminalSaleStatus(status?: string | null) {
  return TERMINAL_SALE_STATUSES.has(String(status ?? '').trim().toLowerCase());
}

export function buildTemplatePayload(
  summary: LateFeeSummary,
  recipients: PaymentReminderRecipients,
  labels: { clientName: string; originalPhone?: string | null; lotLabel: string; saleLabel: string },
  templateName = '',
) {
  if (templateName === DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      buildInstallmentDetail(summary),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      ...buildInstallmentDetailLines(summary, 1),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      ...buildInstallmentDetailLines(summary, 2),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      ...buildInstallmentDetailLines(summary, 3),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      ...buildInstallmentDetailLines(summary, 4),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      ...buildInstallmentDetailLines(summary, 5),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (templateName === PROJECT_PAYMENT_REMINDER_TEMPLATE) {
    return [
      labels.lotLabel,
      String(summary.cantidadCuotasVencidas),
      formatCurrency(summary.capitalPendiente),
      formatCurrency(summary.moraTotal),
      formatCurrency(summary.totalGeneral),
    ];
  }

  if (recipients.mode === 'TEST') {
    const detail = summary.cuotas
      .slice(0, 10)
      .map((cuota) => `Cuota ${cuota.numeroCuota ?? cuota.cuotaSyncId}: venc. ${cuota.fechaVencimiento}, saldo ${formatCurrency(cuota.saldoPendiente)}, mora ${formatCurrency(cuota.mora)}`)
      .join('\n');
    return [
      [
        '🧪 MENSAJE DE PRUEBA — NO ENVIADO AL CLIENTE',
        `Cliente original: ${labels.clientName}`,
        `Telefono original: ${recipients.originalRecipientMasked ?? 'sin telefono'}`,
        `Venta o contrato: ${labels.saleLabel}`,
        `Solar: ${labels.lotLabel}`,
        `Cuotas vencidas: ${summary.cantidadCuotasVencidas}`,
        `Capital pendiente: ${formatCurrency(summary.capitalPendiente)}`,
        `Mora acumulada: ${formatCurrency(summary.moraTotal)}`,
        `Total pendiente: ${formatCurrency(summary.totalGeneral)}`,
        detail,
        'Este mensaje fue redirigido al numero autorizado de pruebas.',
      ].filter(Boolean).join('\n'),
      String(summary.cantidadCuotasVencidas),
      labels.lotLabel,
      labels.saleLabel,
      formatCurrency(summary.capitalPendiente),
      formatCurrency(summary.moraTotal),
      formatCurrency(summary.totalGeneral),
    ];
  }
  return [
    labels.clientName,
    String(summary.cantidadCuotasVencidas),
    labels.lotLabel,
    labels.saleLabel,
    formatCurrency(summary.capitalPendiente),
    formatCurrency(summary.moraTotal),
    formatCurrency(summary.totalGeneral),
  ];
}

export function formatCurrency(value: string) {
  const amount = Number(value);
  const formatted = new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number.isFinite(amount) ? amount : 0);
  return `RD$${formatted}`;
}

export function buildInstallmentDetail(summary: LateFeeSummary) {
  return buildInstallmentDetailLines(summary, summary.cuotas.length)
    .join('\n\n');
}

export function buildInstallmentDetailLines(summary: LateFeeSummary, maxLines: number) {
  const lines = summary.cuotas
    .slice(0, maxLines)
    .map((cuota) => {
      const month = formatInstallmentMonth(cuota.fechaVencimiento);
      return `Cuota mes de ${month}: ${formatCurrency(cuota.saldoPendiente)} mas mora: ${formatCurrency(cuota.mora)}`;
    });
  while (lines.length < maxLines) {
    lines.push('Sin cuota adicional');
  }
  return lines;
}

function formatInstallmentMonth(dateKey: string) {
  const date = new Date(`${dateKey}T00:00:00-04:00`);
  return new Intl.DateTimeFormat('es-DO', {
    month: 'long',
    timeZone: 'America/Santo_Domingo',
  }).format(date) + ` ${date.getFullYear()}`;
}

function notificationData(
  summary: LateFeeSummary,
  input: {
    recipients: PaymentReminderRecipients;
    templateName: string;
    payload: unknown;
    status: string;
  },
) {
  if (!summary.companyId) {
    throw new Error('No hay companyId para reservar notificacion.');
  }
  if (!summary.ultimaCuotaVencidaSyncId) {
    throw new Error('No hay ultima cuota vencida para reservar notificacion.');
  }
  return {
    companyId: summary.companyId,
    clientSyncId: summary.clienteSyncId,
    saleSyncId: summary.ventaSyncId,
    type: PAYMENT_REMINDER_TYPE,
    period: summary.periodoNotificacion,
    lastOverdueInstallmentSyncId: summary.ultimaCuotaVencidaSyncId,
    overdueInstallmentCount: summary.cantidadCuotasVencidas,
    pendingPrincipal: summary.capitalPendiente,
    lateFeeTotal: summary.moraTotal,
    totalDue: summary.totalGeneral,
    destinationPhone: input.recipients.recipients.join(','),
    templateName: input.templateName,
    status: input.status,
    scheduledAt: new Date(),
    payload: input.payload as any,
    testMode: input.recipients.mode === 'TEST',
    redirected: input.recipients.redirected,
    originalRecipientMasked: input.recipients.originalRecipientMasked,
  };
}

function getTemplateInstallmentCapacity(templateName: string) {
  if (templateName === DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE) return 1;
  if (templateName === DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE) return 2;
  if (templateName === DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE) return 3;
  if (templateName === DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE) return 4;
  if (templateName === DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE) return 5;
  return null;
}

export function resolveDetailedTemplateName(baseTemplateName: string, overdueInstallmentCount: number) {
  const detailedTemplates = new Set([
    DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  ]);
  if (!detailedTemplates.has(baseTemplateName)) return baseTemplateName;
  if (overdueInstallmentCount <= 1) return DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE;
  if (overdueInstallmentCount === 2) return DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE;
  if (overdueInstallmentCount === 3) return DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE;
  if (overdueInstallmentCount === 4) return DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE;
  return DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE;
}

function parseTestNumbers() {
  return config.paymentRemindersTestNumbers
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function lotDisplay(lot: { block: string | null; number: string | null }) {
  const block = lot.block?.trim() ?? '';
  const number = lot.number?.trim() ?? '';
  if (block && number) return `M${block}-S${number}`;
  if (number) return `Solar ${number}`;
  if (block) return `Manzana ${block}`;
  return 'No especificado';
}

function isUniqueConstraint(error: unknown) {
  return error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';
}

function logEvent(event: string, data: Record<string, unknown>) {
  console.log(JSON.stringify({ event, ...data }));
}
