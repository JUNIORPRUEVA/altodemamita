import { Router } from 'express';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { PaymentReminderService } from '../services/paymentReminder.service';

export const paymentReminderRouter = Router();
const service = new PaymentReminderService();

paymentReminderRouter.get('/sales/:saleSyncId/overdue-summary', async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const result = await service.getSaleSummary(company.id, req.params.saleSyncId);
  if (!result) {
    return res.status(404).json({ error: { message: 'Venta no encontrada o no elegible.' } });
  }
  return res.json({
    data: {
      summary: result.summary,
      lastNotification: result.lastNotification,
    },
  });
});

paymentReminderRouter.post('/sales/:saleSyncId/send', authGuard, async (req, res) => {
  if (req.user?.role !== 'OWNER') {
    return res.status(403).json({ error: { message: 'No autorizado.' } });
  }
  const company = await resolveCompanyForRequest(req);
  const result = await service.sendSaleReminder({
    companyId: company.id,
    saleSyncId: String(req.params.saleSyncId),
    force: String(req.query.force ?? 'false') === 'true',
    dryRun: req.body?.dryRun,
    forceTestMode: req.body?.forceTestMode === true,
  });
  return res.json({ data: result });
});

paymentReminderRouter.post('/run', authGuard, async (req, res) => {
  if (req.user?.role !== 'OWNER') {
    return res.status(403).json({ error: { message: 'No autorizado.' } });
  }
  const company = await resolveCompanyForRequest(req);
  const stats = await service.processCompany(company.id);
  return res.json({ data: stats });
});

paymentReminderRouter.get('/whatsapp/webhook', (req, res) => {
  const verifyToken = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ?? '';
  if (
    req.query['hub.mode'] === 'subscribe' &&
    req.query['hub.verify_token'] === verifyToken
  ) {
    return res.send(req.query['hub.challenge']);
  }
  return res.sendStatus(403);
});

paymentReminderRouter.post('/whatsapp/webhook', async (req, res) => {
  const statuses = extractWhatsappStatuses(req.body);
  for (const status of statuses) {
    await service.updateWhatsappStatus(status);
  }
  return res.sendStatus(200);
});

function extractWhatsappStatuses(body: any) {
  const statuses: Array<{
    whatsappMessageId: string;
    status: string;
    error?: string | null;
  }> = [];
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      for (const value of change?.value?.statuses ?? []) {
        const error = value?.errors?.[0];
        if (value?.id && value?.status) {
          statuses.push({
            whatsappMessageId: value.id,
            status: String(value.status).toUpperCase(),
            error: error?.message ?? error?.title ?? null,
          });
        }
      }
    }
  }
  return statuses;
}
