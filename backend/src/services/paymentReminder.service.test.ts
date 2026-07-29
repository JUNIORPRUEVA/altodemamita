import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE,
  PROJECT_PAYMENT_REMINDER_TEMPLATE,
  buildTemplatePayload,
  resolveDetailedTemplateName,
} from './paymentReminder.service';
import { resolvePaymentReminderRecipients } from './paymentReminderRecipients.service';

describe('buildTemplatePayload', () => {
  it('en modo prueba incluye cliente/venta, enmascara telefono y no usa telefono completo', () => {
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['18295344286', '18295319442'],
    });
    const payload = buildTemplatePayload(
      {
        companyId: 'company-1',
        clienteId: 'client-1',
        clienteSyncId: 'client-sync-1',
        ventaId: 'sale-1',
        ventaSyncId: 'V-000145',
        fechaCalculo: '2026-08-01',
        cantidadCuotasVencidas: 2,
        capitalPendiente: '20000.00',
        moraTotal: '9200.00',
        totalGeneral: '29200.00',
        ultimaCuotaVencidaSyncId: 'cuota-2',
        periodoNotificacion: '2026-07',
        cuotas: [
          {
            cuotaId: 'cuota-1',
            cuotaSyncId: 'cuota-1',
            numeroCuota: 1,
            fechaVencimiento: '2026-06-01',
            montoOriginal: '10000.00',
            montoPagado: '0.00',
            saldoPendiente: '10000.00',
            diasAtraso: 61,
            tasaDiaria: '0.01',
            mora: '6100.00',
            totalActualizado: '16100.00',
          },
        ],
      },
      recipients,
      {
        clientName: 'Juan Perez',
        originalPhone: '8095551234',
        lotLabel: 'Solar 28',
        saleLabel: 'V-000145',
      },
    );
    const text = payload[0];

    assert.match(text, /MENSAJE DE PRUEBA/);
    assert.match(text, /Juan Perez/);
    assert.match(text, /\*\*\*1234/);
    assert.match(text, /V-000145/);
    assert.match(text, /Solar 28/);
    assert.doesNotMatch(text, /18095551234/);
    assert.doesNotMatch(text, /8095551234/);
  });

  it('para la plantilla del proyecto no incluye nombre, telefono ni contrato', () => {
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['18295319442'],
    });
    const payload = buildTemplatePayload(
      {
        companyId: 'company-1',
        clienteId: 'client-1',
        clienteSyncId: 'client-sync-1',
        ventaId: 'sale-1',
        ventaSyncId: 'V-000145',
        fechaCalculo: '2026-08-01',
        cantidadCuotasVencidas: 2,
        capitalPendiente: '16830.28',
        moraTotal: '5049.08',
        totalGeneral: '21879.36',
        ultimaCuotaVencidaSyncId: 'cuota-2',
        periodoNotificacion: '2026-07',
        cuotas: [],
      },
      recipients,
      {
        clientName: 'Juan Perez',
        originalPhone: '8095551234',
        lotLabel: 'MM-H-S88',
        saleLabel: 'V-000145',
      },
      PROJECT_PAYMENT_REMINDER_TEMPLATE,
    );

    assert.deepEqual(payload, [
      'MM-H-S88',
      '2',
      'RD$16,830.28',
      'RD$5,049.08',
      'RD$21,879.36',
    ]);
    assert.doesNotMatch(payload.join('\n'), /Juan Perez/);
    assert.doesNotMatch(payload.join('\n'), /V-000145/);
    assert.doesNotMatch(payload.join('\n'), /8095551234/);
  });

  it('para la plantilla detallada separa cada cuota con su mora', () => {
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['18295319442'],
    });
    const payload = buildTemplatePayload(
      {
        companyId: 'company-1',
        clienteId: 'client-1',
        clienteSyncId: 'client-sync-1',
        ventaId: 'sale-1',
        ventaSyncId: 'V-000145',
        fechaCalculo: '2026-08-01',
        cantidadCuotasVencidas: 2,
        capitalPendiente: '16830.28',
        moraTotal: '5049.08',
        totalGeneral: '21879.36',
        ultimaCuotaVencidaSyncId: 'cuota-2',
        periodoNotificacion: '2026-07',
        cuotas: [
          {
            cuotaId: 'cuota-1',
            cuotaSyncId: 'cuota-1',
            numeroCuota: 1,
            fechaVencimiento: '2026-06-27',
            montoOriginal: '8415.14',
            montoPagado: '0.00',
            saldoPendiente: '8415.14',
            diasAtraso: 30,
            tasaDiaria: '0.01',
            mora: '2524.54',
            totalActualizado: '10939.68',
          },
          {
            cuotaId: 'cuota-2',
            cuotaSyncId: 'cuota-2',
            numeroCuota: 2,
            fechaVencimiento: '2026-07-27',
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
      recipients,
      {
        clientName: 'Juan Perez',
        originalPhone: '8095551234',
        lotLabel: 'MM-H-S88',
        saleLabel: 'V-000145',
      },
      DETAILED_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    );

    assert.deepEqual(payload, [
      'MM-H-S88',
      'Cuota mes de junio 2026: RD$8,415.14 mas mora: RD$2,524.54\n\nCuota mes de julio 2026: RD$8,415.14 mas mora: RD$84.15',
      'RD$21,879.36',
    ]);
    assert.doesNotMatch(payload.join('\n'), /Juan Perez/);
    assert.doesNotMatch(payload.join('\n'), /V-000145/);
  });

  it('para la plantilla detallada de 3 lineas no usa saltos dentro de variables', () => {
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: true,
      allowRealRecipients: false,
      testNumbers: ['18295319442'],
    });
    const payload = buildTemplatePayload(
      {
        companyId: 'company-1',
        clienteId: 'client-1',
        clienteSyncId: 'client-sync-1',
        ventaId: 'sale-1',
        ventaSyncId: 'V-000145',
        fechaCalculo: '2026-08-01',
        cantidadCuotasVencidas: 2,
        capitalPendiente: '16830.28',
        moraTotal: '5049.08',
        totalGeneral: '21879.36',
        ultimaCuotaVencidaSyncId: 'cuota-2',
        periodoNotificacion: '2026-07',
        cuotas: [
          {
            cuotaId: 'cuota-1',
            cuotaSyncId: 'cuota-1',
            numeroCuota: 1,
            fechaVencimiento: '2026-06-27',
            montoOriginal: '8415.14',
            montoPagado: '0.00',
            saldoPendiente: '8415.14',
            diasAtraso: 30,
            tasaDiaria: '0.01',
            mora: '2524.54',
            totalActualizado: '10939.68',
          },
          {
            cuotaId: 'cuota-2',
            cuotaSyncId: 'cuota-2',
            numeroCuota: 2,
            fechaVencimiento: '2026-07-27',
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
      recipients,
      {
        clientName: 'Juan Perez',
        originalPhone: '8095551234',
        lotLabel: 'MM-H-S88',
        saleLabel: 'V-000145',
      },
      DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    );

    assert.deepEqual(payload, [
      'MM-H-S88',
      'Cuota mes de junio 2026: RD$8,415.14 mas mora: RD$2,524.54',
      'Cuota mes de julio 2026: RD$8,415.14 mas mora: RD$84.15',
      'Sin cuota adicional',
      'RD$21,879.36',
    ]);
    for (const parameter of payload) {
      assert.doesNotMatch(parameter, /[\n\t]/);
    }
  });

  it('para la plantilla detallada de 5 lineas cubre hasta cinco cuotas', () => {
    const recipients = resolvePaymentReminderRecipients({
      customerPhone: '8095551234',
      testMode: false,
      allowRealRecipients: true,
      testNumbers: [],
    });
    const cuotas = ['2026-03-27', '2026-04-27', '2026-05-27', '2026-06-27', '2026-07-27'].map((fechaVencimiento, index) => ({
      cuotaId: `cuota-${index + 1}`,
      cuotaSyncId: `cuota-${index + 1}`,
      numeroCuota: index + 1,
      fechaVencimiento,
      montoOriginal: '8415.14',
      montoPagado: '0.00',
      saldoPendiente: '8415.14',
      diasAtraso: 30,
      tasaDiaria: '0.01',
      mora: '2524.54',
      totalActualizado: '10939.68',
    }));
    const payload = buildTemplatePayload(
      {
        companyId: 'company-1',
        clienteId: 'client-1',
        clienteSyncId: 'client-sync-1',
        ventaId: 'sale-1',
        ventaSyncId: 'V-000145',
        fechaCalculo: '2026-08-01',
        cantidadCuotasVencidas: 5,
        capitalPendiente: '42075.70',
        moraTotal: '12622.70',
        totalGeneral: '54698.40',
        ultimaCuotaVencidaSyncId: 'cuota-5',
        periodoNotificacion: '2026-07',
        cuotas,
      },
      recipients,
      {
        clientName: 'Juan Perez',
        originalPhone: '8095551234',
        lotLabel: 'MM-H-S88',
        saleLabel: 'V-000145',
      },
      DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE,
    );

    assert.equal(payload.length, 7);
    assert.equal(payload[0], 'MM-H-S88');
    assert.equal(payload[1], 'Cuota mes de marzo 2026: RD$8,415.14 mas mora: RD$2,524.54');
    assert.equal(payload[5], 'Cuota mes de julio 2026: RD$8,415.14 mas mora: RD$2,524.54');
    assert.equal(payload[6], 'RD$54,698.40');
    for (const parameter of payload) {
      assert.doesNotMatch(parameter, /[\n\t]/);
    }
  });

  it('elige automaticamente la plantilla detallada segun la cantidad de cuotas', () => {
    assert.equal(resolveDetailedTemplateName(DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE, 1), DETAILED1_PROJECT_PAYMENT_REMINDER_TEMPLATE);
    assert.equal(resolveDetailedTemplateName(DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE, 2), DETAILED2_PROJECT_PAYMENT_REMINDER_TEMPLATE);
    assert.equal(resolveDetailedTemplateName(DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE, 3), DETAILED3_PROJECT_PAYMENT_REMINDER_TEMPLATE);
    assert.equal(resolveDetailedTemplateName(DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE, 4), DETAILED4_PROJECT_PAYMENT_REMINDER_TEMPLATE);
    assert.equal(resolveDetailedTemplateName(DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE, 5), DETAILED5_PROJECT_PAYMENT_REMINDER_TEMPLATE);
    assert.equal(resolveDetailedTemplateName(PROJECT_PAYMENT_REMINDER_TEMPLATE, 2), PROJECT_PAYMENT_REMINDER_TEMPLATE);
  });
});
