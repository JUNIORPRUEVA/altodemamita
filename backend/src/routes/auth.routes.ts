import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { authGuard, bearerToken, signAccessToken } from '../auth';
import { buildAuthContractUser } from '../authContract';
import { resolveCompanyForRequest } from '../companyIdentity';
import { config } from '../config';
import { verifyPassword } from '../password';
import { prisma } from '../prisma';
import { hasPaymentCancellationPermission, permissionSnapshot } from '../rbac';
import { contractPermissionsFor } from '../rbac';
import {
  AdminAuthorizationError,
  PAYMENT_CANCEL_ACTION,
  PAYMENT_RESOURCE_TYPE,
  assertAdminAuthorizationAttemptAllowed,
  clearAdminAuthorizationFailures,
  issueAdminAuthorization,
  registerAdminAuthorizationFailure,
} from '../services/adminAuthorization.service';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  token: z.string().min(1).optional(),
  clientType: z.string().optional(),
});

const authorizeActionSchema = z.object({
  action: z.string().min(1),
  resourceType: z.string().min(1),
  resourceId: z.string().min(1),
  email: z.string().email(),
  password: z.string().min(1),
});

export const authRouter = Router();

authRouter.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { message: 'Credenciales invalidas.' } });
  }

  const email = parsed.data.email.trim().toLowerCase();
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || !user.active) {
    return res.status(401).json({ error: { message: 'Credenciales invalidas.' } });
  }

  const ok = await verifyPassword(parsed.data.password, user.passwordHash);
  if (!ok) {
    return res.status(401).json({ error: { message: 'Credenciales invalidas.' } });
  }

  const sessionUser = {
    id: user.id,
    email: user.email,
    name: user.name,
    role: user.role,
  };

  const accessToken = signAccessToken(sessionUser);
  const contractUser = buildAuthContractUser(
    sessionUser,
    await contractPermissionsFor(user.id, user.role),
  );
  return res.json({
    data: {
      user: contractUser,
      accessToken,
    },
    accessToken,
  });
});

authRouter.post('/refresh', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({ error: { message: 'Token invalido.' } });
  }
  const token = parsed.data.token ?? bearerToken(req);
  if (!token) {
    return res.status(401).json({ error: { message: 'No autenticado.' } });
  }
  try {
    const payload = jwt.verify(token, config.jwtSecret) as { sub?: string };
    const user = await prisma.user.findUnique({ where: { id: String(payload.sub ?? '') } });
    if (!user || !user.active) {
      return res.status(401).json({ error: { message: 'Usuario inactivo.' } });
    }
    const sessionUser = {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
    };
    const accessToken = signAccessToken(sessionUser);
    const contractUser = buildAuthContractUser(
      sessionUser,
      await contractPermissionsFor(user.id, user.role),
    );
    return res.json({ accessToken, data: { accessToken, user: contractUser } });
  } catch {
    return res.status(401).json({ error: { message: 'Sesion invalida.' } });
  }
});

authRouter.get('/me', authGuard, async (req, res) => {
  const snapshot = req.user ? await permissionSnapshot(req.user.id) : { direct: [], roles: [] };
  const contractUser = req.user
    ? buildAuthContractUser(
        req.user,
        await contractPermissionsFor(req.user.id, req.user.role),
      )
    : null;
  const canCancelPayments = req.user
    ? await hasPaymentCancellationPermission(req.user.id, req.user.role)
    : false;
  return res.json({
    data: {
      ...(contractUser ?? {}),
      user: contractUser,
      roles: contractUser?.roles ?? [],
      permissions: contractUser?.permissions ?? [],
      permissionSnapshot: snapshot,
      canCancelPayments,
    },
  });
});

/**
 * Autorizacion administrativa acotada para una accion puntual.
 *
 * El usuario autenticado aporta credenciales de un administrador (OWNER activo)
 * y el backend emite una autorizacion de un solo uso, corta y ligada a la accion
 * y al recurso. La contrasena nunca se almacena, registra ni se reenvia.
 */
authRouter.post('/authorize-action', authGuard, async (req, res) => {
  const parsed = authorizeActionSchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    return res.status(400).json({
      error: { code: 'INVALID_AUTHORIZATION_REQUEST', message: 'Solicitud de autorizacion invalida.' },
    });
  }

  const requester = req.user;
  if (!requester) {
    return res.status(401).json({ error: { message: 'No autenticado.' } });
  }

  const { action, resourceType, resourceId } = parsed.data;
  if (action !== PAYMENT_CANCEL_ACTION || resourceType !== PAYMENT_RESOURCE_TYPE) {
    return res.status(400).json({
      error: {
        code: 'UNSUPPORTED_AUTHORIZATION_ACTION',
        message: 'La accion solicitada no admite autorizacion administrativa.',
      },
    });
  }

  try {
    assertAdminAuthorizationAttemptAllowed(requester.id);
  } catch (error) {
    if (error instanceof AdminAuthorizationError) {
      return res.status(error.status).json({
        error: { code: error.code, message: error.message },
      });
    }
    throw error;
  }

  const email = parsed.data.email.trim().toLowerCase();
  const admin = await prisma.user.findUnique({ where: { email } });
  const passwordOk = admin
    ? await verifyPassword(parsed.data.password, admin.passwordHash)
    : false;
  if (!admin || !admin.active || admin.role !== 'OWNER' || !passwordOk) {
    registerAdminAuthorizationFailure(requester.id);
    return res.status(401).json({
      error: {
        code: 'ADMIN_CREDENTIALS_REJECTED',
        message: 'Las credenciales del administrador no son validas.',
      },
    });
  }

  try {
    const company = await resolveCompanyForRequest(req);
    const payment = await prisma.payment.findFirst({
      where: { id: resourceId, companyId: company.id, deletedAt: null },
      select: { id: true, annulledAt: true, saleId: true },
    });
    if (!payment) {
      return res.status(404).json({
        error: { code: 'PAYMENT_NOT_FOUND', message: 'El pago seleccionado no existe.' },
      });
    }
    if (payment.annulledAt) {
      return res.status(409).json({
        error: { code: 'PAYMENT_ALREADY_ANNULLED', message: 'Este pago ya fue anulado.' },
      });
    }

    clearAdminAuthorizationFailures(requester.id);
    const record = issueAdminAuthorization({
      companyId: company.id,
      action,
      resourceType,
      resourceId,
      requestedByUserId: requester.id,
      authorizedByUserId: admin.id,
      authorizedByName: admin.name,
    });

    return res.json({
      data: {
        authorizationId: record.id,
        action: record.action,
        resourceType: record.resourceType,
        resourceId: record.resourceId,
        expiresAt: new Date(record.expiresAt).toISOString(),
        authorizedBy: { id: admin.id, name: admin.name },
      },
    });
  } catch (error) {
    if (error instanceof AdminAuthorizationError) {
      return res.status(error.status).json({
        error: { code: error.code, message: error.message },
      });
    }
    return res.status(500).json({
      error: {
        code: 'ADMIN_AUTHORIZATION_FAILED',
        message: 'No se pudo emitir la autorizacion. Intenta de nuevo.',
      },
    });
  }
});
