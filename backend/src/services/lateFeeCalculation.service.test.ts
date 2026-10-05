import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { LateFeeCalculationService } from './lateFeeCalculation.service';

const service = new LateFeeCalculationService({ dailyRate: '0.005', graceDays: 5 });
const rdDate = (date: string) => new Date(`${date}T04:00:00.000Z`);

describe('LateFeeCalculationService', () => {
  it('aplica 5 dias completos de gracia y cobra desde el sexto dia posterior al vencimiento', () => {
    const inGrace = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-10-06'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-10-01'),
          totalAmount: '10000',
          paidAmount: '0',
          status: 'pendiente',
        },
      ],
    });
    const firstFeeDay = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-10-07'),
      installments: inGrace.cuotas.map((cuota) => ({
        syncId: cuota.cuotaSyncId,
        dueDate: rdDate(cuota.fechaVencimiento),
        totalAmount: cuota.montoOriginal,
        paidAmount: cuota.montoPagado,
        status: 'pendiente',
      })),
    });

    assert.equal(inGrace.cuotas[0].diasAtraso, 5);
    assert.equal(inGrace.cuotas[0].diasMora, 0);
    assert.equal(inGrace.moraTotal, '0.00');
    assert.equal(firstFeeDay.cuotas[0].diasAtraso, 6);
    assert.equal(firstFeeDay.cuotas[0].diasMora, 1);
    assert.equal(firstFeeDay.moraTotal, '50.00');
  });

  it('no limita la mora a 30 dias', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-04-01'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-01-01'),
          totalAmount: '10000',
          paidAmount: '0',
          status: 'pendiente',
        },
      ],
    });

    assert.equal(summary.cuotas[0].diasAtraso, 90);
    assert.equal(summary.cuotas[0].diasMora, 85);
    assert.equal(summary.moraTotal, '4250.00');
  });

  it('calcula la mora sobre saldo pendiente de cuota, no sobre dinero ya pagado', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-10-11'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-10-01'),
          principalAmount: '8000',
          interestAmount: '2000',
          totalAmount: '10000',
          paidPrincipalAmount: '3000',
          paidInterestAmount: '2000',
          paidAmount: '5000',
          status: 'parcial',
        },
      ],
    });

    assert.equal(summary.cuotas[0].saldoPendiente, '5000.00');
    assert.equal(summary.cuotas[0].interesPendiente, '0.00');
    assert.equal(summary.cuotas[0].capitalPendiente, '5000.00');
    assert.equal(summary.cuotas[0].diasMora, 5);
    assert.equal(summary.moraTotal, '125.00');
  });

  it('respeta pagos parciales posteriores al vencimiento dentro del calculo historico', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-10-16'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-10-01'),
          totalAmount: '10000',
          paidAmount: '4000',
          status: 'parcial',
        },
      ],
      payments: [
        {
          installmentSyncId: 'cuota-1',
          paidAt: rdDate('2026-10-10'),
          amount: '4100',
          principalApplied: '4000',
          interestApplied: '0',
          lateFeeApplied: '100',
        },
      ],
    });

    assert.equal(summary.cuotas[0].saldoPendiente, '6000.00');
    assert.equal(summary.cuotas[0].diasMora, 10);
    assert.equal(summary.moraTotal, '380.00');
  });

  it('redondea dinero a dos decimales usando 0.50%', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-07-08'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-07-01'),
          principalAmount: '1234.567',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
      ],
    });

    assert.equal(summary.capitalPendiente, '1234.57');
    assert.equal(summary.moraTotal, '12.35');
  });

  it('puede deshabilitar la mora sin ocultar la cuota vencida', () => {
    const disabled = new LateFeeCalculationService({ enabled: false, dailyRate: '0.005', graceDays: 5 });
    const summary = disabled.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-12-31'),
      installments: [
        { syncId: 'cuota-1', dueDate: rdDate('2026-07-01'), totalAmount: '10000', paidAmount: '0', status: 'pendiente' },
      ],
    });

    assert.equal(summary.cantidadCuotasVencidas, 1);
    assert.equal(summary.cuotas[0].diasMora, 0);
    assert.equal(summary.moraTotal, '0.00');
  });
});
