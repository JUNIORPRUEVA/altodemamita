import { config } from '../config';
import { prisma } from '../prisma';
import { PaymentReminderService } from '../services/paymentReminder.service';
import {
  isPaymentReminderSendWindowOpen,
  paymentReminderWindowDescription,
} from '../services/paymentReminderWindow.service';

let timer: NodeJS.Timeout | null = null;

export function startPaymentReminderJob() {
  if (!config.paymentRemindersEnabled) {
    console.log(JSON.stringify({ event: 'payment_reminder_job_disabled' }));
    return;
  }
  if (timer) return;

  const run = async () => {
    if (!isPaymentReminderSendWindowOpen(new Date())) {
      console.log(JSON.stringify({
        event: 'payment_reminder_job_skipped_outside_window',
        window: paymentReminderWindowDescription(),
      }));
      return;
    }
    const startedAt = Date.now();
    console.log(JSON.stringify({ event: 'payment_reminder_job_started' }));
    const service = new PaymentReminderService();
    const companies = await prisma.company.findMany({ where: { active: true }, select: { id: true } });
    for (const company of companies) {
      if (!isPaymentReminderSendWindowOpen(new Date())) {
        console.log(JSON.stringify({
          event: 'payment_reminder_job_stopped_outside_window',
          companyId: company.id,
        }));
        break;
      }
      try {
        await service.processCompany(company.id);
      } catch (error) {
        console.log(JSON.stringify({
          event: 'payment_reminder_company_failed',
          companyId: company.id,
          error: error instanceof Error ? error.message.slice(0, 200) : 'unknown',
        }));
      }
    }
    console.log(JSON.stringify({
      event: 'payment_reminder_job_finished',
      durationMs: Date.now() - startedAt,
    }));
  };

  scheduleNextRun(run);
}

function scheduleNextRun(run: () => Promise<void>) {
  const delay = Math.max(nextDominicanCronTime(config.paymentReminderCron).getTime() - Date.now(), 1000);
  timer = setTimeout(async () => {
    try {
      await run();
    } finally {
      scheduleNextRun(run);
    }
  }, delay);
}

function nextDominicanCronTime(cron: string) {
  const { minute, hour } = parseDailyCron(cron);
  const now = new Date();
  const rdNow = new Date(now.getTime() - 4 * 60 * 60 * 1000);
  const next = new Date(Date.UTC(
    rdNow.getUTCFullYear(),
    rdNow.getUTCMonth(),
    rdNow.getUTCDate(),
    hour + 4,
    minute,
    0,
    0,
  ));
  if (next <= now) next.setUTCDate(next.getUTCDate() + 1);
  while (!isPaymentReminderSendWindowOpen(next)) {
    next.setUTCDate(next.getUTCDate() + 1);
  }
  return next;
}

function parseDailyCron(cron: string) {
  const [minuteText, hourText, dayOfMonth, month, dayOfWeek] = cron.trim().split(/\s+/);
  const minute = Number(minuteText);
  const hour = Number(hourText);
  if (
    dayOfMonth !== '*' ||
    month !== '*' ||
    dayOfWeek !== '*' ||
    !Number.isInteger(minute) ||
    !Number.isInteger(hour) ||
    minute < 0 ||
    minute > 59 ||
    hour < 0 ||
    hour > 23
  ) {
    throw new Error('PAYMENT_REMINDER_CRON debe tener formato diario simple, por ejemplo: 0 9 * * *');
  }
  return { minute, hour };
}
