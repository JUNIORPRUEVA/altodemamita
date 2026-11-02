import { Router } from 'express';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';
import { requirePermission } from '../rbac';
import { requirePaymentCancelAuthorization, requireOwnerRole } from '../services/adminAuthorization.service';
import { authoritativeErrorResponse } from '../services/authoritativeErrors.service';
import { AuthoritativePaymentService } from '../services/authoritativePayment.service';
import { AuthoritativeSaleService } from '../services/authoritativeSale.service';
import { InstallmentCorrectionService } from '../services/installmentCorrection.service';
import { SaleCorrectionService } from '../services/saleCorrection.service';
import { EntityAdminService } from '../services/entityAdmin.service';

export const authoritativeRouter = Router();

const sales = new AuthoritativeSaleService(prisma);
const payments = new AuthoritativePaymentService(prisma);
const installmentCorrections = new InstallmentCorrectionService(prisma);
const saleCorrections = new SaleCorrectionService(prisma);
const entityAdmin = new EntityAdminService(prisma);

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
 * FASE 04 — Administracion OWNER de clientes y solares.
 *
 * Reutiliza el patron de las fases anteriores: preview por rollback
 * transaccional, apply atomico/idempotente con version optimista y auditoria.
 */
for (const kind of ['clients', 'lots'] as const) {
  const entityKind = kind === 'clients' ? 'client' : 'lot';

  authoritativeRouter.get(
    `/authoritative/${kind}/:entityId/admin-preview`,
    requireOwnerRole(),
    async (req, res) => {
      try {
        const company = await resolveCompanyForRequest(req);
        const preview = await entityAdmin.preview({
          companyId: company.id,
          kind: entityKind,
          entityId: paramValue(req.params.entityId),
          action: stringValue(req.query.action) as never,
          name: stringValue(req.query.name),
          document: stringValue(req.query.document),
          phone: stringValue(req.query.phone),
          address: stringValue(req.query.address),
          mergeSourceId: stringValue(req.query.mergeSourceId),
          block: stringValue(req.query.block),
          number: stringValue(req.query.number),
          area: numberValue(req.query.area),
          price: numberValue(req.query.price),
          status: stringValue(req.query.status),
        });
        res.status(200).json({ data: preview });
      } catch (error) {
        const response = authoritativeErrorResponse(error);
        res.status(response.status).json(response.body);
      }
    },
  );

  authoritativeRouter.post(
    `/authoritative/${kind}/:entityId/admin`,
    requireOwnerRole(),
    async (req, res) => {
      try {
        const company = await resolveCompanyForRequest(req);
        const body = (req.body ?? {}) as Record<string, unknown>;
        const num = (value: unknown) =>
          value == null || value === '' ? null : Number(value);
        const result = await entityAdmin.apply({
          companyId: company.id,
          kind: entityKind,
          entityId: paramValue(req.params.entityId),
          action: String(body.action ?? '') as never,
          name: body.name == null ? null : String(body.name),
          document: body.document == null ? null : String(body.document),
          phone: body.phone == null ? null : String(body.phone),
          address: body.address == null ? null : String(body.address),
          mergeSourceId:
            body.mergeSourceId == null ? null : String(body.mergeSourceId),
          block: body.block == null ? null : String(body.block),
          number: body.number == null ? null : String(body.number),
          area: num(body.area),
          price: num(body.price),
          status: body.status == null ? null : String(body.status),
          reason: String(body.reason ?? ''),
          performedByUserId: req.user?.id ?? '',
          idempotencyKey: idempotencyKey(req) ?? '',
          expectedVersion:
            body.expectedVersion == null ? null : Number(body.expectedVersion),
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

  authoritativeRouter.get(
    `/authoritative/${kind}/:entityId/admin-audit`,
    requireOwnerRole(),
    async (req, res) => {
      try {
        const company = await resolveCompanyForRequest(req);
        const history = await entityAdmin.history({
          companyId: company.id,
          kind: entityKind,
          entityId: paramValue(req.params.entityId),
        });
        res.status(200).json({ data: history });
      } catch (error) {
        const response = authoritativeErrorResponse(error);
        res.status(response.status).json(response.body);
      }
    },
  );
}

/**
 * FASE 03 — Correccion OWNER de ventas y contratos.
 *
 * `preview` ejecuta la MISMA logica del apply dentro de una transaccion que se
 * revierte: el impacto mostrado es el real. Ninguna accion borra historia: la
 * cancelacion es logica y reversible mediante snapshot auditado.
 */
authoritativeRouter.get(
  '/sales/:saleId/corrections/preview',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const preview = await saleCorrections.previewSaleCorrection({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        action: stringValue(req.query.action) as never,
        saleDate: stringValue(req.query.saleDate),
        totalPrice: numberValue(req.query.totalPrice),
        initialPaidAmount: numberValue(req.query.initialPaidAmount),
        initialRequiredAmount: numberValue(req.query.initialRequiredAmount),
        installmentCount: numberValue(req.query.installmentCount),
        monthlyInterestRate: numberValue(req.query.monthlyInterestRate),
        initialPaymentDeadline: stringValue(req.query.initialPaymentDeadline),
        clientId: stringValue(req.query.clientId),
        lotId: stringValue(req.query.lotId),
      });
      res.status(200).json({ data: preview });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

authoritativeRouter.post(
  '/sales/:saleId/corrections',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const body = (req.body ?? {}) as Record<string, unknown>;
      const numeric = (value: unknown) =>
        value == null || value === '' ? null : Number(value);
      const result = await saleCorrections.applySaleCorrection({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        action: String(body.action ?? '') as never,
        saleDate: body.saleDate == null ? null : String(body.saleDate),
        totalPrice: numeric(body.totalPrice),
        initialPaidAmount: numeric(body.initialPaidAmount),
        initialRequiredAmount: numeric(body.initialRequiredAmount),
        installmentCount: numeric(body.installmentCount),
        monthlyInterestRate: numeric(body.monthlyInterestRate),
        initialPaymentDeadline:
          body.initialPaymentDeadline == null
            ? null
            : String(body.initialPaymentDeadline),
        clientId: body.clientId == null ? null : String(body.clientId),
        lotId: body.lotId == null ? null : String(body.lotId),
        reason: String(body.reason ?? ''),
        performedByUserId: req.user?.id ?? '',
        idempotencyKey: idempotencyKey(req) ?? '',
        expectedSaleVersion:
          body.expectedSaleVersion == null
            ? null
            : Number(body.expectedSaleVersion),
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

authoritativeRouter.get(
  '/sales/:saleId/corrections/audit',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const history = await saleCorrections.getSaleCorrectionHistory({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
      });
      res.status(200).json({ data: history });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

/**
 * FASE 02 — Gestion OWNER del cronograma de cuotas.
 *
 * `preview` ejecuta la MISMA logica del apply dentro de una transaccion que se
 * revierte: el impacto mostrado (capital, proximo vencimiento, mora) es real.
 */
authoritativeRouter.get(
  '/sales/:saleId/installment-corrections/preview',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const preview = await installmentCorrections.previewInstallmentCorrection(
        {
          companyId: company.id,
          saleId: paramValue(req.params.saleId),
          action: stringValue(req.query.action) as never,
          installmentId: stringValue(req.query.installmentId),
          dueDate: stringValue(req.query.dueDate),
          principalAmount: numberValue(req.query.principalAmount),
          interestAmount: numberValue(req.query.interestAmount),
          installmentCount: numberValue(req.query.installmentCount),
          firstDueDate: stringValue(req.query.firstDueDate),
        },
      );
      res.status(200).json({ data: preview });
    } catch (error) {
      const response = authoritativeErrorResponse(error);
      res.status(response.status).json(response.body);
    }
  },
);

authoritativeRouter.post(
  '/sales/:saleId/installment-corrections',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const body = (req.body ?? {}) as Record<string, unknown>;
      const result = await installmentCorrections.applyInstallmentCorrection({
        companyId: company.id,
        saleId: paramValue(req.params.saleId),
        action: String(body.action ?? '') as never,
        installmentId: body.installmentId == null ? null : String(body.installmentId),
        dueDate: body.dueDate == null ? null : String(body.dueDate),
        principalAmount:
          body.principalAmount == null || body.principalAmount === ''
            ? null
            : Number(body.principalAmount),
        interestAmount:
          body.interestAmount == null || body.interestAmount === ''
            ? null
            : Number(body.interestAmount),
        installmentCount:
          body.installmentCount == null || body.installmentCount === ''
            ? null
            : Number(body.installmentCount),
        firstDueDate: body.firstDueDate == null ? null : String(body.firstDueDate),
        reason: String(body.reason ?? ''),
        performedByUserId: req.user?.id ?? '',
        idempotencyKey: idempotencyKey(req) ?? '',
        expectedSaleVersion:
          body.expectedSaleVersion == null
            ? null
            : Number(body.expectedSaleVersion),
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

authoritativeRouter.get(
  '/sales/:saleId/installment-corrections/audit',
  requireOwnerRole(),
  async (req, res) => {
    try {
      const company = await resolveCompanyForRequest(req);
      const history = await installmentCorrections.getInstallmentCorrectionHistory(
        { companyId: company.id, saleId: paramValue(req.params.saleId) },
      );
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

/** Numero opcional desde query string: `undefined` si falta o no es numerico. */
function numberValue(value: unknown) {
  const text = Array.isArray(value) ? value[0] : value;
  if (text == null || text === '') {
    return null;
  }
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : null;
}
