import assert from 'node:assert/strict';
import test from 'node:test';
import {
  BUSINESS_TIMEZONE,
  dateKeyInTimeZone,
  isPastDueBusinessDay,
  resolveEffectiveInstallmentStatus,
  summarizeInstallments,
} from './installmentStatus.service';
import { addMonths } from './financing.service';

const businessDate = new Date('2026-09-15T12:00:00.000-04:00');

test('uses America/Santo_Domingo as the canonical business timezone', () => {
  assert.equal(BUSINESS_TIMEZONE, 'America/Santo_Domingo');
  assert.equal(
    dateKeyInTimeZone(new Date('2026-09-16T03:30:00.000Z')),
    '2026-09-15',
  );
});

test('classifies future, due-today, and yesterday installments deterministically', () => {
  assert.equal(
    resolveEffectiveInstallmentStatus({
      storedStatus: 'pendiente',
      dueDate: new Date('2026-09-16T15:11:00.000Z'),
      totalAmount: 1000,
      paidAmount: 0,
      businessDate,
    }),
    'pendiente',
  );
  assert.equal(
    resolveEffectiveInstallmentStatus({
      storedStatus: 'pendiente',
      dueDate: new Date('2026-09-15T15:11:00.000Z'),
      totalAmount: 1000,
      paidAmount: 0,
      businessDate,
    }),
    'pendiente',
  );
  assert.equal(
    resolveEffectiveInstallmentStatus({
      storedStatus: 'pendiente',
      dueDate: new Date('2026-09-14T15:11:00.000Z'),
      totalAmount: 1000,
      paidAmount: 0,
      businessDate,
    }),
    'vencida',
  );
});

test('closed and paid installments do not become overdue by date', () => {
  for (const storedStatus of ['pagada', 'ajustada', 'cancelada']) {
    assert.equal(
      resolveEffectiveInstallmentStatus({
        storedStatus,
        dueDate: new Date('2026-09-01T15:11:00.000Z'),
        totalAmount: 1000,
        paidAmount: storedStatus === 'pagada' ? 1000 : 0,
        businessDate,
      }),
      storedStatus,
    );
  }
});

test('partial installments remain partial while current and become overdue when past due', () => {
  assert.equal(
    resolveEffectiveInstallmentStatus({
      storedStatus: 'parcial',
      dueDate: new Date('2026-09-16T15:11:00.000Z'),
      totalAmount: 1000,
      paidAmount: 250,
      businessDate,
    }),
    'parcial',
  );
  assert.equal(
    resolveEffectiveInstallmentStatus({
      storedStatus: 'parcial',
      dueDate: new Date('2026-09-14T15:11:00.000Z'),
      totalAmount: 1000,
      paidAmount: 250,
      businessDate,
    }),
    'vencida',
  );
});

test('summarizes paid, overdue, partial, and pending installments without pending=total-paid', () => {
  const summary = summarizeInstallments(
    [
      { dueDate: '2026-09-01T12:00:00.000Z', totalAmount: 1000, paidAmount: 1000 },
      { dueDate: '2026-09-01T12:00:00.000Z', totalAmount: 1000, paidAmount: 0 },
      { dueDate: '2026-09-20T12:00:00.000Z', totalAmount: 1000, paidAmount: 250 },
      { dueDate: '2026-10-20T12:00:00.000Z', totalAmount: 1000, paidAmount: 0 },
    ],
    { businessDate },
  );

  assert.deepEqual(summary, {
    total: 4,
    paid: 1,
    overdue: 1,
    partial: 1,
    pending: 1,
  });
});

test('Iluminada conceptual schedule derives first two due dates from saleDate', () => {
  const saleDate = new Date(2026, 6, 15, 15, 11, 0);
  assert.equal(addMonths(saleDate, 1).toISOString().slice(0, 10), '2026-08-15');
  assert.equal(addMonths(saleDate, 2).toISOString().slice(0, 10), '2026-09-15');
  assert.equal(
    isPastDueBusinessDay({ dueDate: addMonths(saleDate, 1), businessDate }),
    true,
  );
  assert.equal(
    isPastDueBusinessDay({ dueDate: addMonths(saleDate, 2), businessDate }),
    false,
  );
});

test('month-end and leap-year due dates follow the sale-date month rule', () => {
  assert.equal(addMonths(new Date(2026, 0, 31), 1).toISOString().slice(0, 10), '2026-02-28');
  assert.equal(addMonths(new Date(2028, 0, 31), 1).toISOString().slice(0, 10), '2028-02-29');
  assert.equal(addMonths(new Date(2026, 2, 30), 1).toISOString().slice(0, 10), '2026-04-30');
});
