import { config } from '../config';

export function isPaymentReminderSendWindowOpen(date = new Date()) {
  const rd = dominicanParts(date);
  if (config.paymentReminderStartDate && rd.dateKey < config.paymentReminderStartDate) {
    return false;
  }
  const allowedDays = new Set(
    config.paymentReminderAllowedDays
      .split(',')
      .map((value) => Number(value.trim()))
      .filter((value) => Number.isInteger(value)),
  );
  if (!allowedDays.has(rd.dayOfWeek)) return false;
  return rd.hour >= config.paymentReminderWindowStartHour && rd.hour < config.paymentReminderWindowEndHour;
}

export function paymentReminderWindowDescription() {
  return {
    timezone: config.paymentReminderTimezone,
    startDate: config.paymentReminderStartDate || null,
    allowedDays: config.paymentReminderAllowedDays,
    startHour: config.paymentReminderWindowStartHour,
    endHour: config.paymentReminderWindowEndHour,
  };
}

function dominicanParts(date: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Santo_Domingo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
    weekday: 'short',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const weekdayMap: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  };
  return {
    dateKey: `${values.year}-${values.month}-${values.day}`,
    hour: Number(values.hour),
    dayOfWeek: weekdayMap[values.weekday] ?? -1,
  };
}
