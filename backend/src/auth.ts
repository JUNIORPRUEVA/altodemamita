import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { config } from './config';
import { prisma } from './prisma';

export type AuthUser = {
  id: string;
  email: string;
  name: string;
  role: 'OWNER' | 'TECH';
};

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

const tokenSchema = z.object({
  sub: z.string(),
  email: z.string(),
  role: z.enum(['OWNER', 'TECH']),
});

export function signAccessToken(user: AuthUser) {
  return jwt.sign(
    {
      sub: user.id,
      email: user.email,
      role: user.role,
    },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn as any },
  );
}

export async function authGuard(req: Request, res: Response, next: NextFunction) {
  const header = req.header('authorization') ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) {
    return res.status(401).json({ error: { message: 'No autenticado.' } });
  }

  try {
    const payload = tokenSchema.parse(jwt.verify(token, config.jwtSecret));
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || !user.active) {
      return res.status(401).json({ error: { message: 'Usuario inactivo.' } });
    }
    req.user = {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
    };
    return next();
  } catch {
    return res.status(401).json({ error: { message: 'Sesion invalida.' } });
  }
}

export function syncGuard(req: Request, res: Response, next: NextFunction) {
  const token = req.header('x-sync-token')?.trim() ?? '';
  if (!token || token !== config.syncDeviceToken) {
    return res.status(401).json({ error: { message: 'Sync no autorizado.' } });
  }
  return next();
}
