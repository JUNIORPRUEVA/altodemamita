import { Prisma } from '@prisma/client';
import { config } from '../config';
import { prisma } from '../prisma';
import { LateFeeCalculationService, LateFeeSummary } from './lateFeeCalculation.service';
import { paymentReminderWindowDescription } from './paymentReminderWindow.service';
import { normalizeWhatsappPhone } from './whatsapp.service';

export const PAYMENT_REMINDER_CONFIG_KEYS = {
  enabled: 'payment_reminders_enabled',
  senderWhatsappNumber: 'payment_reminders_sender_whatsapp_number',
  messageFragment: 'payment_reminders_message_fragment',
} as const;

const defaultMessageFragment = 'Te recordamos que tienes cuotas vencidas pendientes de pago.';
const terminalSaleStatuses = new Set(['pagada', 'cancelada', 'anulada', 'cerrada', 'saldada']);
const candidatePreviewLimit = 8;

export async function getPaymentReminderAdminState(companyId: string) {
  const [items, lastNotification, statsRows, deliveries, candidates] = await Promise.all([
    configurationMap(companyId),
    prisma.paymentReminderNotification.findFirst({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.paymentReminderDelivery.groupBy({
      by: ['status'],
      where: { notification: { companyId } },
      _count: { _all: true },
    }),
    prisma.paymentReminderDelivery.findMany({
      where: { notification: { companyId } },
      include: { notification: true },
      orderBy: { createdAt: 'desc' },
      take: 30,
    }),
    summarizeReminderCandidates(companyId),
  ]);

  const clientNames = await namesByClientSyncId(
    companyId,
    deliveries.map((item) => item.notification.clientSyncId).filter((value): value is string => Boolean(value)),
  );
  const requestedEnabled = boolValue(items.get(PAYMENT_REMINDER_CONFIG_KEYS.enabled)?.value, config.paymentRemindersEnabled);
  const senderWhatsappNumber = items.get(PAYMENT_REMINDER_CONFIG_KEYS.senderWhatsappNumber)?.value ?? '';
  const messageFragment = items.get(PAYMENT_REMINDER_CONFIG_KEYS.messageFragment)?.value ?? defaultMessageFragment;
  const stats = statusCounts(statsRows);
  const whatsappConfigured = isWhatsappProviderConfigured();

  return {
    config: {
      notificationsEnabled: requestedEnabled,
      effectiveEnabled: effectiveReminderEnabled(requestedEnabled),
      senderWhatsAppNumber: senderWhatsappNumber,
      editableMessageFragment: messageFragment,
      maxMessageFragmentLength: 250,
      templateLocked: true,
      activeTemplateName: config.whatsappPaymentTemplate,
      testTemplateName: config.whatsappPaymentTestTemplate,
      templateLanguage: config.whatsappTemplateLanguage,
    },
    system: {
      deliveryGateEnabled: config.paymentRemindersEnabled,
      emergencyStop: config.paymentRemindersEmergencyStop,
      dryRun: config.paymentRemindersDryRun,
      testMode: config.paymentRemindersTestMode,
      allowRealRecipients: config.paymentRemindersAllowRealRecipients,
      whatsappConfigured,
      displayWhatsappConfigured: senderWhatsappNumber.trim().length > 0,
      whatsappPhoneNumberId: maskConfigId(config.whatsappPhoneNumberId),
      whatsappBusinessAccountId: maskConfigId(config.whatsappBusinessAccountId),
      schedule: paymentReminderWindowDescription(),
      runFrequency: describeRunFrequency(),
      retryPolicy: 'El trabajo automatico corre una vez al dia. Si un envio falla, queda registrado como FAILED; puede reintentarse en una corrida futura o con envio manual forzado, sin duplicar el mismo periodo/cuota ya reservado.',
      recipientPolicy: recipientPolicyDescription(),
      duplicatePolicy: 'Para una misma venta, tipo de recordatorio y ultima cuota vencida, el sistema reserva una sola notificacion. Asi evita mandar el mismo recordatorio repetido por reintentos.',
      templatePolicy: 'WhatsApp solo permite enviar plantillas aprobadas en Meta. Desde aqui se editan los valores administrables y la vista previa; cambiar el cuerpo fijo requiere aprobar otra plantilla en Meta.',
      nextRun: null,
    },
    template: {
      locked: true,
      editableFields: templateEditableFields(messageFragment),
      preview: buildAdminPreview(messageFragment),
    },
    candidates,
    lastRun: lastNotification
      ? {
          id: lastNotification.id,
          status: lastNotification.status,
          processedCount: lastNotification.overdueInstallmentCount,
          createdAt: lastNotification.createdAt.toISOString(),
          sentAt: lastNotification.sentAt?.toISOString() ?? null,
        }
      : null,
    stats,
    history: deliveries.map((delivery) => deliveryDto(delivery, clientNames)),
  };
}

export async function updatePaymentReminderAdminConfig(
  companyId: string,
  input: {
    notificationsEnabled?: boolean;
    senderWhatsAppNumber?: string | null;
    editableMessageFragment?: string;
  },
) {
  if (input.notificationsEnabled !== undefined) {
    await upsertConfiguration(companyId, PAYMENT_REMINDER_CONFIG_KEYS.enabled, input.notificationsEnabled ? 'true' : 'false', 'Activa o desactiva recordatorios automaticos de cuotas vencidas.');
  }

  if (input.senderWhatsAppNumber !== undefined) {
    const normalized = normalizeDisplayWhatsappNumber(input.senderWhatsAppNumber);
    await upsertConfiguration(companyId, PAYMENT_REMINDER_CONFIG_KEYS.senderWhatsappNumber, normalized, 'Numero visible de WhatsApp utilizado como canal emisor.');
  }

  if (input.editableMessageFragment !== undefined) {
    const normalized = normalizeMessageFragment(input.editableMessageFragment);
    await upsertConfiguration(companyId, PAYMENT_REMINDER_CONFIG_KEYS.messageFragment, normalized, 'Fragmento editable presentado en la vista previa del recordatorio.');
  }

  return getPaymentReminderAdminState(companyId);
}

export async function isPaymentReminderEnabledForCompany(companyId: string) {
  if (!config.paymentRemindersEnabled || config.paymentRemindersEmergencyStop) {
    return false;
  }
  const row = await prisma.businessConfiguration.findUnique({
    where: {
      companyId_key: {
        companyId,
        key: PAYMENT_REMINDER_CONFIG_KEYS.enabled,
      },
    },
    select: { value: true, deletedAt: true },
  });
  if (row?.deletedAt) {
    return false;
  }
  return boolValue(row?.value, true);
}

export function effectiveReminderEnabled(requestedEnabled: boolean) {
  return (
    requestedEnabled &&
    config.paymentRemindersEnabled &&
    !config.paymentRemindersEmergencyStop &&
    !config.paymentRemindersDryRun &&
    !config.paymentRemindersTestMode &&
    config.paymentRemindersAllowRealRecipients &&
    isWhatsappProviderConfigured()
  );
}

export function isWhatsappProviderConfigured() {
  return Boolean(
    config.whatsappAccessToken.trim() &&
      config.whatsappPhoneNumberId.trim() &&
      config.whatsappBusinessAccountId.trim(),
  );
}

async function summarizeReminderCandidates(companyId: string) {
  const calculator = new LateFeeCalculationService({
    dailyRate: config.lateFeeDailyRate,
    timezone: config.paymentReminderTimezone,
  });
  const sales = await prisma.sale.findMany({
    where: { companyId, deletedAt: null },
    select: { id: true, syncId: true, status: true, clientSyncId: true, lotSyncId: true },
  });
  const activeSales = sales.filter((sale) => !terminalSaleStatuses.has(String(sale.status ?? '').trim().toLowerCase()));
  const saleSyncIds = activeSales.map((sale) => sale.syncId);
  if (saleSyncIds.length === 0) {
    return emptyCandidateSummary(sales.length);
  }

  const [clients, lots, installments, payments] = await Promise.all([
    prisma.client.findMany({
      where: {
        companyId,
        syncId: { in: activeSales.map((sale) => sale.clientSyncId).filter((value): value is string => Boolean(value)) },
        deletedAt: null,
      },
      select: { id: true, syncId: true, name: true, phone: true },
    }),
    prisma.lot.findMany({
      where: {
        companyId,
        syncId: { in: activeSales.map((sale) => sale.lotSyncId).filter((value): value is string => Boolean(value)) },
        deletedAt: null,
      },
      select: { syncId: true, block: true, number: true },
    }),
    prisma.installment.findMany({
      where: { companyId, saleSyncId: { in: saleSyncIds }, deletedAt: null },
      orderBy: [{ dueDate: 'asc' }, { installmentNumber: 'asc' }],
    }),
    prisma.payment.findMany({
      where: { companyId, saleSyncId: { in: saleSyncIds }, deletedAt: null },
      orderBy: { paidAt: 'asc' },
    }),
  ]);

  const clientsBySyncId = new Map(clients.map((client) => [client.syncId, client]));
  const lotsBySyncId = new Map(lots.map((lot) => [lot.syncId, lot]));
  const installmentsBySale = groupBy(installments, (item) => item.saleSyncId ?? '');
  const paymentsBySale = groupBy(payments, (item) => item.saleSyncId ?? '');
  const preview: Array<{
    saleSyncId: string;
    clientName: string;
    phoneMasked: string;
    lotLabel: string;
    overdueInstallments: number;
    totalDue: string;
    status: string;
  }> = [];
  let overdueSales = 0;
  let withValidPhone = 0;
  let blockedWithoutPhone = 0;
  let totalOverdueInstallments = 0;
  let totalDue = new Prisma.Decimal(0);

  for (const sale of activeSales) {
    const client = sale.clientSyncId ? clientsBySyncId.get(sale.clientSyncId) : null;
    const lot = sale.lotSyncId ? lotsBySyncId.get(sale.lotSyncId) : null;
    const summary = calculator.calculateSaleSummary({
      context: {
        companyId,
        clienteId: client?.id ?? null,
        clientSyncId: sale.clientSyncId,
        clienteNombre: client?.name ?? null,
        clienteTelefono: client?.phone ?? null,
        ventaId: sale.id,
        saleSyncId: sale.syncId,
        lotLabel: lot ? lotDisplay(lot) : null,
      },
      installments: installmentsBySale.get(sale.syncId) ?? [],
      payments: paymentsBySale.get(sale.syncId) ?? [],
    });
    if (summary.cantidadCuotasVencidas <= 0 || !summary.ultimaCuotaVencidaSyncId) continue;
    overdueSales += 1;
    totalOverdueInstallments += summary.cantidadCuotasVencidas;
    totalDue = totalDue.plus(summary.totalGeneral);
    const normalizedPhone = normalizeWhatsappPhone(client?.phone ?? '');
    if (normalizedPhone) {
      withValidPhone += 1;
    } else {
      blockedWithoutPhone += 1;
    }
    preview.push(candidateDto(summary, client?.name, lot ? lotDisplay(lot) : null, normalizedPhone));
  }

  preview.sort((a, b) => Number(b.totalDue) - Number(a.totalDue));
  return {
    totalSales: sales.length,
    activeSales: activeSales.length,
    overdueSales,
    withValidPhone,
    blockedWithoutPhone,
    totalOverdueInstallments,
    totalDue: totalDue.toDecimalPlaces(2, Prisma.Decimal.ROUND_HALF_UP).toFixed(2),
    preview: preview.slice(0, candidatePreviewLimit),
  };
}

function emptyCandidateSummary(totalSales: number) {
  return {
    totalSales,
    activeSales: 0,
    overdueSales: 0,
    withValidPhone: 0,
    blockedWithoutPhone: 0,
    totalOverdueInstallments: 0,
    totalDue: '0.00',
    preview: [],
  };
}

function candidateDto(
  summary: LateFeeSummary,
  clientName?: string | null,
  lotLabel?: string | null,
  normalizedPhone?: string | null,
) {
  return {
    saleSyncId: summary.ventaSyncId,
    clientName: clientName?.trim() || 'Cliente',
    phoneMasked: normalizedPhone ? maskPhone(normalizedPhone) : 'Sin WhatsApp valido',
    lotLabel: lotLabel ?? 'Solar no especificado',
    overdueInstallments: summary.cantidadCuotasVencidas,
    totalDue: summary.totalGeneral,
    status: normalizedPhone ? 'READY' : 'BLOCKED_PHONE',
  };
}

function groupBy<T>(items: T[], keyFor: (item: T) => string) {
  const grouped = new Map<string, T[]>();
  for (const item of items) {
    const key = keyFor(item);
    if (!key) continue;
    grouped.set(key, [...(grouped.get(key) ?? []), item]);
  }
  return grouped;
}

function templateEditableFields(messageFragment: string) {
  return [
    { key: 'editableMessageFragment', label: 'Mensaje administrativo', value: messageFragment, editable: true },
    { key: 'lotLabel', label: 'Solar vendido', value: 'Se calcula desde la venta', editable: false },
    { key: 'installmentDetails', label: 'Cuotas vencidas, capital y mora', value: 'Se calcula desde cuotas y pagos', editable: false },
    { key: 'totalDue', label: 'Total pendiente', value: 'Se calcula con 1% diario de mora hasta 30 dias por cuota', editable: false },
  ];
}

function buildAdminPreview(messageFragment: string) {
  return [
    'Hola Cliente.',
    '',
    messageFragment,
    '',
    'Solar: M8-S24',
    'Cuotas vencidas: 2',
    'Detalle: cuota mayo 2026 RD$8,415.14 + mora RD$2,524.54',
    'Total vencido: RD$21,879.36',
  ].join('\n');
}

function describeRunFrequency() {
  const schedule = paymentReminderWindowDescription();
  return `Corre una vez al dia segun cron ${config.paymentReminderCron}, dentro de ${schedule.timezone}.`;
}

function recipientPolicyDescription() {
  if (config.paymentRemindersTestMode) {
    return 'Modo prueba activo: los mensajes se redirigen a los numeros de prueba autorizados y no al cliente real.';
  }
  if (!config.paymentRemindersAllowRealRecipients) {
    return 'Destinatarios reales bloqueados: aunque existan clientes elegibles, el sistema no envia al telefono real.';
  }
  return 'Destinatarios reales permitidos: se usa el telefono WhatsApp del cliente cuando es valido.';
}

async function configurationMap(companyId: string) {
  const rows = await prisma.businessConfiguration.findMany({
    where: {
      companyId,
      deletedAt: null,
      key: { in: Object.values(PAYMENT_REMINDER_CONFIG_KEYS) },
    },
  });
  return new Map(rows.map((row) => [row.key, row]));
}

async function upsertConfiguration(companyId: string, key: string, value: string, description: string) {
  await prisma.businessConfiguration.upsert({
    where: { companyId_key: { companyId, key } },
    create: { companyId, key, value, description },
    update: { value, description, deletedAt: null, version: { increment: 1 } },
  });
}

async function namesByClientSyncId(companyId: string, syncIds: string[]) {
  const unique = [...new Set(syncIds)];
  if (unique.length === 0) {
    return new Map<string, string>();
  }
  const clients = await prisma.client.findMany({
    where: { companyId, syncId: { in: unique } },
    select: { syncId: true, name: true },
  });
  return new Map(clients.map((client) => [client.syncId, client.name]));
}

function statusCounts(rows: Array<{ status: string; _count: { _all: number } }>) {
  const counts: Record<string, number> = {
    sent: 0,
    delivered: 0,
    read: 0,
    failed: 0,
    pending: 0,
    dryRun: 0,
  };
  for (const row of rows) {
    switch (row.status) {
      case 'SENT':
        counts.sent += row._count._all;
        break;
      case 'DELIVERED':
        counts.delivered += row._count._all;
        break;
      case 'READ':
        counts.read += row._count._all;
        break;
      case 'FAILED':
        counts.failed += row._count._all;
        break;
      case 'DRY_RUN':
        counts.dryRun += row._count._all;
        break;
      default:
        counts.pending += row._count._all;
        break;
    }
  }
  return counts;
}

function deliveryDto(
  delivery: Prisma.PaymentReminderDeliveryGetPayload<{
    include: { notification: true };
  }>,
  clientNames: Map<string, string>,
) {
  const clientSyncId = delivery.notification.clientSyncId ?? '';
  return {
    id: delivery.id,
    clientName: clientNames.get(clientSyncId) ?? 'Cliente',
    phoneMasked: delivery.originalRecipientMasked ?? maskPhone(delivery.actualRecipient),
    status: delivery.status,
    saleSyncId: delivery.notification.saleSyncId,
    installmentCount: delivery.notification.overdueInstallmentCount,
    scheduledAt: delivery.notification.scheduledAt?.toISOString() ?? null,
    sentAt: delivery.sentAt?.toISOString() ?? null,
    deliveredAt: delivery.deliveredAt?.toISOString() ?? null,
    readAt: delivery.readAt?.toISOString() ?? null,
    createdAt: delivery.createdAt.toISOString(),
  };
}

function boolValue(value: string | null | undefined, fallback: boolean) {
  if (value == null) {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (['true', '1', 'yes', 'si', 'sí'].includes(normalized)) return true;
  if (['false', '0', 'no'].includes(normalized)) return false;
  return fallback;
}

function normalizeDisplayWhatsappNumber(value: string | null | undefined) {
  const trimmed = value?.trim() ?? '';
  if (!trimmed) {
    return '';
  }
  const normalized = normalizeWhatsappPhone(trimmed);
  if (!normalized) {
    throw new PaymentReminderAdminValidationError('INVALID_WHATSAPP_NUMBER', 'Ingresa un numero de WhatsApp dominicano valido con codigo de pais.');
  }
  return `+${normalized}`;
}

function normalizeMessageFragment(value: string) {
  const normalized = value.replace(/\s+/g, ' ').trim();
  if (!normalized) {
    throw new PaymentReminderAdminValidationError('EMPTY_MESSAGE_FRAGMENT', 'El mensaje no puede quedar vacio.');
  }
  if (normalized.length > 250) {
    throw new PaymentReminderAdminValidationError('MESSAGE_FRAGMENT_TOO_LONG', 'El mensaje no puede superar 250 caracteres.');
  }
  if (/\{\{|\}\}/.test(normalized)) {
    throw new PaymentReminderAdminValidationError('MESSAGE_FRAGMENT_HAS_TEMPLATE_VARIABLES', 'No escribas variables de plantilla en el texto personalizado.');
  }
  return normalized;
}

function maskPhone(value: string) {
  const digits = value.replace(/\D/g, '');
  if (digits.length < 4) {
    return 'Telefono oculto';
  }
  const last = digits.slice(-4);
  if (digits.length >= 11) {
    return `+${digits.slice(0, 1)} ${digits.slice(1, 4)} *** ${last}`;
  }
  return `***${last}`;
}

function maskConfigId(value: string) {
  const normalized = value.trim();
  if (!normalized) {
    return '';
  }
  if (normalized.length <= 4) {
    return '****';
  }
  return `****${normalized.slice(-4)}`;
}

function lotDisplay(lot: { block: string | null; number: string | null }) {
  const block = lot.block?.trim() ?? '';
  const number = lot.number?.trim() ?? '';
  if (block && number) return `M${block}-S${number}`;
  if (number) return `Solar ${number}`;
  if (block) return `Manzana ${block}`;
  return 'No especificado';
}

export class PaymentReminderAdminValidationError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}
