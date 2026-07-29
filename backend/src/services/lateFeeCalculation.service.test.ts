import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { LateFeeCalculationService } from './lateFeeCalculation.service';

const service = new LateFeeCalculationService({ dailyRate: '0.01' });
const rdDate = (date: string) => new Date(`${date}T04:00:00.000Z`);

describe('LateFeeCalculationService', () => {
  it('calcula una cuota vencida al 1% diario', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-08-01'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-07-22'),
          principalAmount: '10000',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
      ],
    });

    assert.equal(summary.capitalPendiente, '10000.00');
    assert.equal(summary.moraTotal, '1000.00');
    assert.equal(summary.totalGeneral, '11000.00');
  });

  it('calcula cada cuota con su propio vencimiento y consolida totales', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-08-01'),
      installments: [
        {
          syncId: 'cuota-1',
          installmentNumber: 1,
          dueDate: rdDate('2026-06-01'),
          principalAmount: '10000',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
        {
          syncId: 'cuota-2',
          installmentNumber: 2,
          dueDate: rdDate('2026-07-01'),
          principalAmount: '10000',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
      ],
    });

    assert.equal(summary.cuotas[0].diasAtraso, 61);
    assert.equal(summary.cuotas[0].mora, '3000.00');
    assert.equal(summary.cuotas[1].diasAtraso, 31);
    assert.equal(summary.cuotas[1].mora, '3000.00');
    assert.equal(summary.capitalPendiente, '20000.00');
    assert.equal(summary.moraTotal, '6000.00');
    assert.equal(summary.totalGeneral, '26000.00');
  });

  it('no calcula mora sobre mora', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-07-11'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-07-01'),
          principalAmount: '10000',
          paidPrincipalAmount: '4000',
          status: 'parcial',
        },
      ],
    });

    assert.equal(summary.capitalPendiente, '6000.00');
    assert.equal(summary.moraTotal, '600.00');
  });

  it('respeta pagos parciales posteriores al vencimiento cuando hay fecha por cuota', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-07-21'),
      installments: [
        {
          syncId: 'cuota-1',
          dueDate: rdDate('2026-07-01'),
          principalAmount: '10000',
          paidPrincipalAmount: '4000',
          status: 'parcial',
        },
      ],
      payments: [
        {
          installmentSyncId: 'cuota-1',
          paidAt: rdDate('2026-07-11'),
          amount: '4000',
        },
      ],
    });

    assert.equal(summary.capitalPendiente, '6000.00');
    assert.equal(summary.moraTotal, '1600.00');
  });

  it('excluye cuotas pagadas, futuras y que vencen hoy', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-08-01'),
      installments: [
        { syncId: 'pagada', dueDate: rdDate('2026-06-01'), principalAmount: '10000', paidPrincipalAmount: '10000', status: 'pagada' },
        { syncId: 'hoy', dueDate: rdDate('2026-08-01'), principalAmount: '10000', paidPrincipalAmount: '0', status: 'pendiente' },
        { syncId: 'futura', dueDate: rdDate('2026-08-02'), principalAmount: '10000', paidPrincipalAmount: '0', status: 'pendiente' },
      ],
    });

    assert.equal(summary.cantidadCuotasVencidas, 0);
    assert.equal(summary.totalGeneral, '0.00');
  });

  it('consolida tres cuotas vencidas sin mezclar dias de atraso', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-08-01'),
      installments: [
        { syncId: 'cuota-1', dueDate: rdDate('2026-05-01'), principalAmount: '1000', paidPrincipalAmount: '0', status: 'pendiente' },
        { syncId: 'cuota-2', dueDate: rdDate('2026-06-01'), principalAmount: '1000', paidPrincipalAmount: '0', status: 'pendiente' },
        { syncId: 'cuota-3', dueDate: rdDate('2026-07-01'), principalAmount: '1000', paidPrincipalAmount: '0', status: 'pendiente' },
      ],
    });

    assert.deepEqual(summary.cuotas.map((cuota) => cuota.diasAtraso), [92, 61, 31]);
    assert.equal(summary.moraTotal, '900.00');
  });

  it('reduce la base antes del vencimiento cuando el pago parcial ocurrio antes', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-07-11'),
      installments: [
        { syncId: 'cuota-1', dueDate: rdDate('2026-07-01'), principalAmount: '10000', paidPrincipalAmount: '4000', status: 'parcial' },
      ],
      payments: [
        { installmentSyncId: 'cuota-1', paidAt: rdDate('2026-06-25'), amount: '4000' },
      ],
    });

    assert.equal(summary.capitalPendiente, '6000.00');
    assert.equal(summary.moraTotal, '600.00');
  });

  it('ignora cuotas canceladas o ajustadas', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-08-01'),
      installments: [
        { syncId: 'cancelada', dueDate: rdDate('2026-06-01'), principalAmount: '10000', paidPrincipalAmount: '0', status: 'cancelada' },
        { syncId: 'ajustada', dueDate: rdDate('2026-06-01'), principalAmount: '10000', paidPrincipalAmount: '0', status: 'ajustada' },
      ],
    });

    assert.equal(summary.cantidadCuotasVencidas, 0);
  });

  it('redondea dinero a dos decimales y usa 0.01 como 1%', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-1' },
      calculationDate: rdDate('2026-07-02'),
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

  it('usa el monto total de la cuota como saldo pendiente cuando incluye capital e interes', () => {
    const summary = service.calculateSaleSummary({
      context: { saleSyncId: 'venta-real' },
      calculationDate: rdDate('2026-07-27'),
      installments: [
        {
          syncId: 'cuota-4',
          installmentNumber: 4,
          dueDate: rdDate('2026-05-27'),
          principalAmount: '2627.01',
          interestAmount: '5788.13',
          totalAmount: '8415.14',
          paidAmount: '0',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
        {
          syncId: 'cuota-5',
          installmentNumber: 5,
          dueDate: rdDate('2026-06-27'),
          principalAmount: '2653.28',
          interestAmount: '5761.86',
          totalAmount: '8415.14',
          paidAmount: '0',
          paidPrincipalAmount: '0',
          status: 'pendiente',
        },
      ],
    });

    assert.equal(summary.capitalPendiente, '16830.28');
    assert.equal(summary.cuotas[0].diasAtraso, 61);
    assert.equal(summary.cuotas[0].mora, '2524.54');
    assert.equal(summary.cuotas[1].diasAtraso, 30);
    assert.equal(summary.cuotas[1].mora, '2524.54');
    assert.equal(summary.moraTotal, '5049.08');
    assert.equal(summary.totalGeneral, '21879.36');
  });
});
