import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { Prisma } from '@prisma/client';
import { config } from '../config';
import { prisma } from '../prisma';
import { PaymentReminderService } from './paymentReminder.service';

const originalConfig = {
  emergencyStop: config.paymentRemindersEmergencyStop,
  testMode: config.paymentRemindersTestMode,
  allowRealRecipients: config.paymentRemindersAllowRealRecipients,
  testNumbers: config.paymentRemindersTestNumbers,
};

const originalCreate = prisma.paymentReminderNotification.create;
const originalUpsertDelivery = prisma.paymentReminderDelivery.upsert;
const originalFindDeliveries = prisma.paymentReminderDelivery.findMany;
const originalCreateSnapshots = prisma.lateFeeSnapshot.createMany;

describe('PaymentReminderService dry run audit', () => {
  afterEach(() => {
    config.paymentRemindersEmergencyStop = originalConfig.emergencyStop;
    config.paymentRemindersTestMode = originalConfig.testMode;
    config.paymentRemindersAllowRealRecipients = originalConfig.allowRealRecipients;
    config.paymentRemindersTestNumbers = originalConfig.testNumbers;
    prisma.paymentReminderNotification.create = originalCreate;
    prisma.paymentReminderDelivery.upsert = originalUpsertDelivery;
    prisma.paymentReminderDelivery.findMany = originalFindDeliveries;
    prisma.lateFeeSnapshot.createMany = originalCreateSnapshots;
  });

  it('persiste notificacion, entregas y snapshot sin enviar al proveedor', async () => {
    config.paymentRemindersEmergencyStop = false;
    config.paymentRemindersTestMode = true;
    config.paymentRemindersAllowRealRecipients = false;
    config.paymentRemindersTestNumbers = '18295344286,18295319442';

    const createdNotifications: unknown[] = [];
    const createdDeliveries: unknown[] = [];
    const snapshots: unknown[] = [];
    prisma.paymentReminderNotification.create = (async (args: unknown) => {
      createdNotifications.push(args);
      return { id: 'notification-1' };
    }) as typeof prisma.paymentReminderNotification.create;
    prisma.paymentReminderDelivery.upsert = (async (args: unknown) => {
      createdDeliveries.push(args);
      return {};
    }) as typeof prisma.paymentReminderDelivery.upsert;
    prisma.paymentReminderDelivery.findMany = (async () => []) as typeof prisma.paymentReminderDelivery.findMany;
    prisma.lateFeeSnapshot.createMany = (async (args: unknown) => {
      snapshots.push(args);
      return { count: 1 };
    }) as typeof prisma.lateFeeSnapshot.createMany;

    const service = new PaymentReminderService();
    (service as any).getSaleSummary = async () => saleSummary();
    (service as any).whatsapp = {
      sendTemplateMessage: async () => {
        throw new Error('WhatsApp must not be called in dry run.');
      },
    };

    const result = await service.sendSaleReminder({
      companyId: 'company-1',
      saleSyncId: 'sale-sync-1',
      calculationDate: new Date('2026-07-29T13:00:00.000Z'),
      dryRun: true,
    });

    assert.equal(result.status, 'DRY_RUN');
    assert.equal(result.notificationId, 'notification-1');
    assert.equal(createdNotifications.length, 1);
    assert.equal((createdNotifications[0] as any).data.status, 'DRY_RUN');
    assert.equal(createdDeliveries.length, 2);
    assert.equal((createdDeliveries[0] as any).create.status, 'DRY_RUN');
    assert.equal(snapshots.length, 1);
    assert.equal((snapshots[0] as any).data[0].eventType, 'DRY_RUN');
  });

  it('bloquea dry-run duplicado con la misma llave logica', async () => {
    config.paymentRemindersEmergencyStop = false;
    config.paymentRemindersTestMode = true;
    config.paymentRemindersAllowRealRecipients = false;
    config.paymentRemindersTestNumbers = '18295344286';

    prisma.paymentReminderNotification.create = (async () => {
      throw new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
        code: 'P2002',
        clientVersion: 'test',
      });
    }) as unknown as typeof prisma.paymentReminderNotification.create;

    const service = new PaymentReminderService();
    (service as any).getSaleSummary = async () => saleSummary();
    (service as any).whatsapp = {
      sendTemplateMessage: async () => {
        throw new Error('WhatsApp must not be called for duplicate dry run.');
      },
    };

    const result = await service.sendSaleReminder({
      companyId: 'company-1',
      saleSyncId: 'sale-sync-1',
      calculationDate: new Date('2026-07-29T13:00:00.000Z'),
      dryRun: true,
    });

    assert.equal(result.status, 'SKIPPED_DUPLICATE');
  });
});

function saleSummary() {
  return {
    sale: { syncId: 'sale-sync-1' },
    client: { name: 'Cliente Prueba', phone: '8095551234' },
    lot: { block: 'H', number: '88' },
    lastNotification: null,
    summary: {
      companyId: 'company-1',
      clienteId: 'client-1',
      clienteSyncId: 'client-sync-1',
      ventaId: 'sale-1',
      ventaSyncId: 'sale-sync-1',
      fechaCalculo: '2026-07-29',
      cantidadCuotasVencidas: 1,
      capitalPendiente: '8415.14',
      moraTotal: '84.15',
      totalGeneral: '8499.29',
      ultimaCuotaVencidaSyncId: 'installment-sync-1',
      periodoNotificacion: '2026-07',
      cuotas: [
        {
          cuotaId: 'installment-1',
          cuotaSyncId: 'installment-sync-1',
          numeroCuota: 1,
          fechaVencimiento: '2026-07-28',
          montoOriginal: '8415.14',
          montoPagado: '0.00',
          saldoPendiente: '8415.14',
          diasAtraso: 1,
          tasaDiaria: '0.01',
          mora: '84.15',
          totalActualizado: '8499.29',
        },
      ],
    },
  };
}
