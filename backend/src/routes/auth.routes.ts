import { Router } from 'express';
import { z } from 'zod';
import { authGuard, signAccessToken } from '../auth';
import { verifyPassword } from '../password';
import { prisma } from '../prisma';

const loginSchema = z.object({
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

  return res.json({
    data: {
      user: sessionUser,
      accessToken: signAccessToken(sessionUser),
    },
  });
});

authRouter.get('/me', authGuard, (req, res) => {
  return res.json({ data: { user: req.user } });
});
