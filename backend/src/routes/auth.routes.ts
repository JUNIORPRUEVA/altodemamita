import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { authGuard, bearerToken, signAccessToken } from '../auth';
import { buildAuthContractUser } from '../authContract';
import { config } from '../config';
import { verifyPassword } from '../password';
import { prisma } from '../prisma';
import { permissionSnapshot } from '../rbac';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const refreshSchema = z.object({
  token: z.string().min(1).optional(),
  clientType: z.string().optional(),
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
  const contractUser = buildAuthContractUser(sessionUser);
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
    const contractUser = buildAuthContractUser(sessionUser);
    return res.json({ accessToken, data: { accessToken, user: contractUser } });
  } catch {
    return res.status(401).json({ error: { message: 'Sesion invalida.' } });
  }
});

authRouter.get('/me', authGuard, async (req, res) => {
  const snapshot = req.user ? await permissionSnapshot(req.user.id) : { direct: [], roles: [] };
  const contractUser = req.user ? buildAuthContractUser(req.user) : null;
  return res.json({
    data: {
      ...(contractUser ?? {}),
      user: contractUser,
      roles: contractUser?.roles ?? [],
      permissions: contractUser?.permissions ?? [],
      permissionSnapshot: snapshot,
    },
  });
});
