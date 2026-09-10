import { randomUUID } from 'crypto';
import type { NextFunction, Request, Response } from 'express';
import { resolveCompanyForRequest } from '../companyIdentity';
import { hasPaymentCancellationPermission } from '../rbac';

/**
 * Autorizacion administrativa acotada.
 *
 * El backend es la autoridad: un usuario sin permiso `pagos/anular` no puede
 * anular un pago por si mismo, pero puede solicitar que un administrador
 * habilite ESA accion sobre ESE pago puntual. La autorizacion:
 *  - es de un solo uso,
 *  - expira en una ventana corta,
 *  - esta ligada a (compania, accion, tipo de recurso, id de recurso y solicitante).
 *
 * No se crea una sesion administrativa completa ni se reutiliza la sesion del
 * administrador. La contrasena del administrador nunca se almacena, registra ni
 * se propaga: solo se verifica una vez en el endpoint de autorizacion.
 */

export const PAYMENT_CANCEL_ACTION = 'payments.cancel';
export const PAYMENT_RESOURCE_TYPE = 'PAYMENT';

const AUTHORIZATION_TTL_MS = 2 * 60 * 1000;
const MAX_STORED_AUTHORIZATIONS = 500;

export type AdminAuthorizationRecord = {
  id: string;
  companyId: string;
  action: string;
  resourceType: string;
  resourceId: string;
  requestedByUserId: string;
  authorizedByUserId: string;
  authorizedByName: string;
  expiresAt: number;
  consumedAt: number | null;
};

export type PaymentCancellationContext = {
  authorizedByUserId: string | null;
  authorizationId: string | null;
};

declare global {
  namespace Express {
    interface Request {
      paymentCancellation?: PaymentCancellationContext;
    }
  }
}

export class AdminAuthorizationError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

const authorizations = new Map<string, AdminAuthorizationRecord>();

let clock: () => number = () => Date.now();

/** Solo para pruebas: permite controlar el reloj usado por las expiraciones. */
export function __setAdminAuthorizationClockForTest(next: (() => number) | null) {
  clock = next ?? (() => Date.now());
}

function now() {
  return clock();
}

function purgeExpired(now: number) {
  for (const [id, record] of authorizations) {
    if (record.expiresAt <= now || record.consumedAt !== null) {
      authorizations.delete(id);
    }
  }
  while (authorizations.size >= MAX_STORED_AUTHORIZATIONS) {
    const oldest = authorizations.keys().next().value;
    if (oldest === undefined) break;
    authorizations.delete(oldest);
  }
}

export function issueAdminAuthorization(input: {
  companyId: string;
  action: string;
  resourceType: string;
  resourceId: string;
  requestedByUserId: string;
  authorizedByUserId: string;
  authorizedByName: string;
}) {
  const issuedAt = now();
  purgeExpired(issuedAt);
  const record: AdminAuthorizationRecord = {
    id: `admauth_${randomUUID()}`,
    companyId: input.companyId,
    action: input.action,
    resourceType: input.resourceType,
    resourceId: input.resourceId,
    requestedByUserId: input.requestedByUserId,
    authorizedByUserId: input.authorizedByUserId,
    authorizedByName: input.authorizedByName,
    expiresAt: issuedAt + AUTHORIZATION_TTL_MS,
    consumedAt: null,
  };
  authorizations.set(record.id, record);
  return record;
}

export function consumeAdminAuthorization(input: {
  id: string;
  companyId: string;
  action: string;
  resourceType: string;
  resourceId: string;
  requestedByUserId: string;
}) {
  const record = authorizations.get(input.id);
  if (!record) {
    throw new AdminAuthorizationError(
      'ADMIN_AUTHORIZATION_NOT_FOUND',
      'La autorizacion de administrador no existe o ya fue utilizada. Solicita una nueva.',
      403,
    );
  }
  if (record.consumedAt !== null) {
    throw new AdminAuthorizationError(
      'ADMIN_AUTHORIZATION_ALREADY_USED',
      'Esta autorizacion ya fue utilizada. Solicita una nueva.',
      403,
    );
  }
  if (record.expiresAt <= now()) {
    authorizations.delete(record.id);
    throw new AdminAuthorizationError(
      'ADMIN_AUTHORIZATION_EXPIRED',
      'La autorizacion de administrador expiro. Solicita una nueva.',
      403,
    );
  }
  const matches =
    record.companyId === input.companyId &&
    record.action === input.action &&
    record.resourceType === input.resourceType &&
    record.resourceId === input.resourceId &&
    record.requestedByUserId === input.requestedByUserId;
  if (!matches) {
    throw new AdminAuthorizationError(
      'ADMIN_AUTHORIZATION_MISMATCH',
      'La autorizacion no corresponde a esta operacion. Solicita una nueva.',
      403,
    );
  }

  record.consumedAt = now();
  return record;
}

/**
 * Middleware de anulacion de pagos.
 *
 * Camino directo: OWNER o usuario con permiso efectivo de anulacion.
 * Camino con override: usuario sin permiso que aporta una autorizacion
 * administrativa valida emitida por `POST /api/auth/authorize-action`.
 */
export function requirePaymentCancelAuthorization() {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: { message: 'No autenticado.' } });
    }

    if (await hasPaymentCancellationPermission(req.user.id, req.user.role)) {
      req.paymentCancellation = { authorizedByUserId: null, authorizationId: null };
      return next();
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const authorizationId = stringValue(body.adminAuthorizationId);
    if (!authorizationId) {
      return res.status(403).json({
        error: {
          code: 'PAYMENT_CANCEL_AUTHORIZATION_REQUIRED',
          message:
            'Necesitas autorizacion de un administrador para anular este pago.',
        },
      });
    }

    const paymentId = Array.isArray(req.params.paymentId)
      ? req.params.paymentId[0]
      : req.params.paymentId ?? '';
    try {
      const company = await resolveCompanyForRequest(req);
      const record = consumeAdminAuthorization({
        id: authorizationId,
        companyId: company.id,
        action: PAYMENT_CANCEL_ACTION,
        resourceType: PAYMENT_RESOURCE_TYPE,
        resourceId: String(paymentId),
        requestedByUserId: req.user.id,
      });
      req.paymentCancellation = {
        authorizedByUserId: record.authorizedByUserId,
        authorizationId: record.id,
      };
      return next();
    } catch (error) {
      if (error instanceof AdminAuthorizationError) {
        return res.status(error.status).json({
          error: { code: error.code, message: error.message },
        });
      }
      return res.status(500).json({
        error: { code: 'ADMIN_AUTHORIZATION_FAILED', message: 'No se pudo validar la autorizacion.' },
      });
    }
  };
}

function stringValue(value: unknown) {
  if (typeof value !== 'string') return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

const MAX_FAILED_ATTEMPTS = 5;
const ATTEMPT_WINDOW_MS = 5 * 60 * 1000;
const failedAttempts = new Map<string, { count: number; resetAt: number }>();

/** Limita el intento de adivinar la contrasena del administrador. */
export function assertAdminAuthorizationAttemptAllowed(userId: string) {
  const entry = failedAttempts.get(userId);
  if (!entry) return;
  if (entry.resetAt <= now()) {
    failedAttempts.delete(userId);
    return;
  }
  if (entry.count >= MAX_FAILED_ATTEMPTS) {
    throw new AdminAuthorizationError(
      'ADMIN_AUTHORIZATION_THROTTLED',
      'Demasiados intentos fallidos. Espera unos minutos e intenta de nuevo.',
      429,
    );
  }
}

export function registerAdminAuthorizationFailure(userId: string) {
  const currentTime = now();
  const entry = failedAttempts.get(userId);
  if (!entry || entry.resetAt <= currentTime) {
    failedAttempts.set(userId, { count: 1, resetAt: currentTime + ATTEMPT_WINDOW_MS });
    return;
  }
  entry.count += 1;
}

export function clearAdminAuthorizationFailures(userId: string) {
  failedAttempts.delete(userId);
}

/** Solo para pruebas: reinicia el almacen en memoria. */
export function __resetAdminAuthorizations() {
  authorizations.clear();
  failedAttempts.clear();
}
