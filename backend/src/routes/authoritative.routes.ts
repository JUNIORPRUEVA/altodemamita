import { Router } from 'express';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';
import { requirePermission } from '../rbac';
import { requirePaymentCancelAuthorization } from '../services/adminAuthorization.service';
import { authoritativeErrorResponse } from '../services/authoritativeErrors.service';
import { AuthoritativePaymentService } from '../services/authoritativePayment.service';
import { AuthoritativeSaleService } from '../services/authoritativeSale.service';

export const authoritativeRouter = Router();

const sales = new AuthoritativeSaleService(prisma);
const payments = new AuthoritativePaymentService(prisma);

authoritativeRouter.use(authGuard);

authoritativeRouter.post('/sales', requirePermission('sales', 'create'), async (req, res) => {
  try {
    const company = await resolveCompanyForRequest(req);
    const result = await sales.createSale({
      ...(req.body as Record<string, never>),
      companyId: company.id,
      operatorUserId: req.user?.id ?? '',
      idempotencyKey: idempotencyKey(req) ?? '',
    });
    res.status(result.replayed ? 200 : 201).json({
      data: result.response,
      idempotentReplay: result.replayed,
    });
  } catch (error) {
    const response = authoritativeErrorResponse(error);
    res.status(response.status).json(response.body);
  }
});

authoritativeRouter.post('/payments', requirePermission('payments', 'create'), async (req, res) => {
  try {
    const company = await resolveCompanyForRequest(req);
    const result = await payments.registerPayment({
      ...(req.body as Record<string, never>),
      companyId: company.id,
      receivedByUserId: req.user?.id ?? '',
      idempotencyKey: idempotencyKey(req) ?? '',
    });
    res.status(result.replayed ? 200 : 201).json({
      data: result.response,
      idempotentReplay: result.replayed,
    });
  } catch (error) {
    const response = authoritativeErrorResponse(error);
    res.status(response.status).json(response.body);
  }
});

authoritativeRouter.post(
  '/payments/:paymentId/annul',
  requirePaymentCancelAuthorization(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const result = await payments.annulPayment({
        ...(req.body as Record<string, never>),
        companyId: company.id,
        annulledByUserId: req.user?.id ?? '',
        authorizedByUserId: req.paymentCancellation?.authorizedByUserId ?? null,
        paymentId: paramValue(req.params.paymentId),
        idempotencyKey: idempotencyKey(req) ?? '',
      });
      res.status(result.replayed ? 200 : 201).json({
        data: result.response,
        idempotentReplay: result.replayed,
      });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

authoritativeRouter.post('/sales/:saleId/cancel', requirePermission('sales', 'delete'), async (req, res) => {
  try {
    const company = await resolveCompanyForRequest(req);
    const result = await sales.cancelSale({
      ...(req.body as Record<string, never>),
      companyId: company.id,
      cancelledByUserId: req.user?.id ?? '',
      saleId: paramValue(req.params.saleId),
      idempotencyKey: idempotencyKey(req) ?? '',
    });
    res.status(result.replayed ? 200 : 201).json({
      data: result.response,
      idempotentReplay: result.replayed,
    });
  } catch (error) {
    const response = authoritativeErrorResponse(error);
    res.status(response.status).json(response.body);
  }
});

function idempotencyKey(req: { header: (name: string) => string | undefined; body?: unknown }) {
  const body = req.body as Record<string, unknown> | undefined;
  return (
    req.header('idempotency-key') ??
    stringValue(body?.idempotencyKey) ??
    stringValue(body?.operationId)
  );
}

function stringValue(value: unknown) {
  if (typeof value !== 'string') {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function paramValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value ?? '';
}
