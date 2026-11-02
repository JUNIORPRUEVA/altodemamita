import { Router } from 'express';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';
import { requirePermission } from '../rbac';
import { requirePaymentCancelAuthorization, requireOwnerRole } from '../services/adminAuthorization.service';
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

authoritativeRouter.get(
  '/sales/:saleId/settlement-quote',
  requirePermission('payments', 'read'),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const quote = await payments.getSettlementQuote({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        asOfDate: stringValue(req.query.asOfDate),
      });
      res.status(200).json({ data: quote });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

/**
 * Fase 2 (Windows) — Mora autoritativa (bruto / cobrado / condonado / exigible).
 * Permite que el cliente muestre el monto cobrable sin recalcular localmente.
 */
authoritativeRouter.get(
  '/sales/:saleId/late-fee-summary',
  requirePermission('payments', 'read'),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const summary = await payments.getLateFeeSummary({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        asOfDate: stringValue(req.query.asOfDate),
      });
      res.status(200).json({ data: summary });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

/**
 * Condonacion persistente de mora (solo OWNER). El monto lo calcula el backend
 * al `cutoffAt`; nunca se acepta un importe desde el cliente.
 */
authoritativeRouter.post(
  '/sales/:saleId/late-fee-waiver',
  async (req, res) => {
    if (req.user?.role !== 'OWNER') {
      return res.status(403).json({
        error: { code: 'FORBIDDEN', message: 'No autorizado.' },
      });
    }
    try {
      const company = await resolveCompanyForRequest(req);
      const body = (req.body ?? {}) as Record<string, unknown>;
      const result = await payments.waiveLateFees({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        operatorUserId: req.user?.id ?? '',
        idempotencyKey: idempotencyKey(req) ?? '',
        confirmSaleSyncId: String(body.confirmSaleSyncId ?? ''),
        cutoffAt: String(body.cutoffAt ?? ''),
        reason: String(body.reason ?? ''),
        waivedAmount:
          body.waivedAmount == null || body.waivedAmount === ''
            ? null
            : Number(body.waivedAmount),
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

authoritativeRouter.post(
  '/sales/:saleId/settle',
  requirePermission('payments', 'create'),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const result = await payments.settleSale({
        ...(req.body as Record<string, never>),
        companyId: company.id,
        receivedByUserId: req.user?.id ?? '',
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
  },
);

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

/**
 * FASE 01C — Correccion de pagos historicos (solo OWNER).
 *
 * `correction-preview` es SOLO LECTURA: devuelve si la operacion es segura y el
 * impacto financiero estimado, para que el escritorio muestre el efecto exacto
 * antes de confirmar.
 */
authoritativeRouter.get(
  '/payments/:paymentId/correction-preview',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const rawAmount = stringValue(req.query.newAmount);
      const preview = await payments.previewPaymentCorrection({
        companyId: company.id,
        paymentId: paramValue(req.params.paymentId),
        action: stringValue(req.query.action) as never,
        newDate: stringValue(req.query.newDate),
        newAmount:
          rawAmount == null || rawAmount === ''
            ? null
            : Number(rawAmount),
      });
      res.status(200).json({ data: preview });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

/**
 * FASE 01D — Traza administrativa de un pago (SOLO LECTURA, solo OWNER).
 */
authoritativeRouter.get(
  '/payments/:paymentId/correction-history',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const history = await payments.getPaymentCorrectionHistory({
        companyId: company.id,
        paymentId: paramValue(req.params.paymentId),
      });
      res.status(200).json({ data: history });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

/**
 * FASE 01C — Aplica una correccion historica (solo OWNER).
 *
 * Requiere motivo y (recomendado) la version del pago para control optimista.
 * Idempotente por cabecera `Idempotency-Key`.
 */
authoritativeRouter.post(
  '/payments/:paymentId/correct',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const body = (req.body ?? {}) as Record<string, unknown>;
      const expectedVersion = body.expectedPaymentVersion;
      const result = await payments.applyPaymentCorrection({
        companyId: company.id,
        paymentId: paramValue(req.params.paymentId),
        action: String(body.action ?? '') as never,
        newDate: body.newDate == null ? null : String(body.newDate),
        newAmount:
          body.newAmount == null || body.newAmount === ''
            ? null
            : Number(body.newAmount),
        reason: String(body.reason ?? ''),
        performedByUserId: req.user?.id ?? '',
        idempotencyKey: idempotencyKey(req) ?? '',
        expectedPaymentVersion:
          expectedVersion == null ? null : Number(expectedVersion),
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
