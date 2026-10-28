import assert from 'node:assert/strict';
import test from 'node:test';
import { LateFeeCalculationService } from './lateFeeCalculation.service';
import { sumWaivedLateFee } from './lateFeeWaiver.service';

const TZ = 'America/Santo_Domingo';

function calculator() {
  return new LateFeeCalculationService({
    enabled: true,
    dailyRate: '0.005',
    graceDays: 5,
    timezone: TZ,
  });
}

const installment = {
  syncId: 'inst-1',
  saleSyncId: 'sale-1',
  installmentNumber: 1,
  dueDate: new Date('2026-08-24T12:00:00-04:00'),
  totalAmount: 5166.76,
  paidAmount: 3675.81,
  principalAmount: 1687.7,
  interestAmount: 3479.06,
  status: 'parcial',
};

const calculationDate = new Date('2026-10-27T12:00:00-04:00');

function summarize(
  waivers?: Array<{ installmentSyncId?: string | null; waivedAmount?: number; cutoffAt?: Date }>,
) {
  return calculator().calculateSaleSummary({
    context: { companyId: 'c1', saleSyncId: 'sale-1' },
    installments: [installment],
    payments: [],
    waivers,
    calculationDate,
  });
}

test('sin condonaciones: mora exigible = mora bruta', () => {
  const summary = summarize();
  assert.equal(summary.moraTotal, '439.83');
  assert.equal(summary.moraBruta, '439.83');
  assert.equal(summary.moraCondonada, '0.00');
});

test('condonacion a nivel de venta cubre toda la mora acumulada', () => {
  const summary = summarize([{ installmentSyncId: null, waivedAmount: 439.83 }]);
  assert.equal(summary.moraTotal, '0.00');
  assert.equal(summary.moraBruta, '439.83');
  assert.equal(summary.moraCondonada, '439.83');
  assert.equal(summary.cuotas[0].mora, '0.00');
  assert.equal(summary.cuotas[0].moraBruta, '439.83');
});

test('condonacion mayor que la mora se recorta (no genera saldo negativo)', () => {
  const summary = summarize([{ installmentSyncId: null, waivedAmount: 1000 }]);
  assert.equal(summary.moraTotal, '0.00');
  assert.equal(summary.moraCondonada, '439.83');
});

test('condonacion parcial deja mora exigible remanente', () => {
  const summary = summarize([{ installmentSyncId: 'inst-1', waivedAmount: 100 }]);
  assert.equal(summary.moraTotal, '339.83');
  assert.equal(summary.moraCondonada, '100.00');
});

test('la condonacion con corte no absorbe la mora posterior al corte', () => {
  const atCutoff = summarize([
    { installmentSyncId: null, waivedAmount: 439.83, cutoffAt: calculationDate },
  ]);
  assert.equal(atCutoff.moraTotal, '0.00');

  const later = calculator().calculateSaleSummary({
    context: { companyId: 'c1', saleSyncId: 'sale-1' },
    installments: [installment],
    payments: [],
    waivers: [
      { installmentSyncId: null, waivedAmount: 439.83, cutoffAt: calculationDate },
    ],
    calculationDate: new Date('2026-10-29T12:00:00-04:00'),
  });
  assert.equal(later.moraBruta, '454.74');
  assert.equal(later.moraCondonada, '439.83');
  assert.equal(later.moraTotal, '14.91');
});

test('una condonacion mayor que la mora al corte no cubre mora futura', () => {
  const later = calculator().calculateSaleSummary({
    context: { companyId: 'c1', saleSyncId: 'sale-1' },
    installments: [installment],
    payments: [],
    waivers: [
      { installmentSyncId: null, waivedAmount: 1000, cutoffAt: calculationDate },
    ],
    calculationDate: new Date('2026-10-29T12:00:00-04:00'),
  });
  assert.equal(later.moraCondonada, '439.83');
  assert.equal(later.moraTotal, '14.91');
});

test('la condonacion por cuota no se aplica a otra cuota', () => {
  const summary = calculator().calculateSaleSummary({
    context: { companyId: 'c1', saleSyncId: 'sale-1' },
    installments: [
      installment,
      {
        ...installment,
        syncId: 'inst-2',
        installmentNumber: 2,
        dueDate: new Date('2026-09-24T12:00:00-04:00'),
        paidAmount: 0,
        totalAmount: 5166.76,
      },
    ],
    payments: [],
    waivers: [{ installmentSyncId: 'inst-1', waivedAmount: 439.83 }],
    calculationDate,
  });
  assert.equal(summary.cuotas[0].mora, '0.00');
  assert.ok(Number(summary.cuotas[1].mora) > 0);
  assert.equal(summary.moraBruta, String((439.83 + Number(summary.cuotas[1].moraBruta)).toFixed(2)));
});

test('sumWaivedLateFee suma los montos condonados', () => {
  assert.equal(sumWaivedLateFee([{ waivedAmount: 13 }, { waivedAmount: '13.00' as unknown as number }]), 26);
  assert.equal(sumWaivedLateFee([]), 0);
});

test('la condonacion no altera el capital pendiente', () => {
  const withoutWaiver = summarize();
  const withWaiver = summarize([{ installmentSyncId: null, waivedAmount: 439.83 }]);
  assert.equal(withWaiver.capitalPendiente, withoutWaiver.capitalPendiente);
  assert.equal(withWaiver.capitalPendiente, '1490.95');
});
