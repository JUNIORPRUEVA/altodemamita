import { UserRole } from '@prisma/client';
import { config } from './config';
import { hashPassword } from './password';
import { prisma } from './prisma';

async function ensureUser(params: {
  email: string;
  password: string;
  name: string;
  role: UserRole;
}) {
  const email = params.email.trim().toLowerCase();
  const password = params.password.trim();
  if (!email || !password) return;

  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) return;

  await prisma.user.create({
    data: {
      email,
      name: params.name.trim() || email,
      passwordHash: await hashPassword(password),
      role: params.role,
    },
  });
}

export async function bootstrapUsers() {
  await ensureUser({
    email: config.ownerEmail,
    password: config.ownerPassword,
    name: config.ownerName,
    role: UserRole.OWNER,
  });
  await ensureUser({
    email: config.techEmail,
    password: config.techPassword,
    name: config.techName,
    role: UserRole.TECH,
  });
}
