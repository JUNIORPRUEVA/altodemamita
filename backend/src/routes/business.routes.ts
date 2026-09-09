import { Router } from 'express';
import { z } from 'zod';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { hashPassword } from '../password';
import { prisma } from '../prisma';
import { permissionDomains, requirePermission } from '../rbac';

export const businessRouter = Router();

const permissionDomainSet = new Set<string>(permissionDomains);
const allowedBusinessConfigKeys = new Set([
  'business_name',
  'receipt_footer',
  'default_currency',
  'payment_terms',
  'late_fee_policy',
  'invoice_prefix',
]);

businessRouter.use(authGuard);

businessRouter.get('/users', requirePermission('users', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const users = await prisma.user.findMany({
    where: { OR: [{ companyId: company.id }, { companyId: null }], deletedAt: null },
    orderBy: { email: 'asc' },
    select: {
      id: true,
      email: true,
      name: true,
      role: true,
      active: true,
      localRole: true,
      phone: true,
      companyId: true,
    },
  });
  return res.json({ data: { users } });
});

businessRouter.post('/users', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z
    .object({
      email: z.string().email(),
      password: z.string().min(8),
      name: z.string().min(1),
      role: z.enum(['OWNER', 'TECH']).default('TECH'),
      phone: z.string().optional(),
      active: z.boolean().default(true),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_USER', message: 'Usuario invalido.' } });
  }
  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      email: parsed.data.email.trim().toLowerCase(),
      name: parsed.data.name.trim(),
      role: parsed.data.role,
      phone: parsed.data.phone,
      active: parsed.data.active,
      passwordHash: await hashPassword(parsed.data.password),
    },
    select: { id: true, email: true, name: true, role: true, active: true, companyId: true },
  });
  return res.status(201).json({ data: { user } });
});

businessRouter.get('/roles', requirePermission('users', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const roles = await prisma.businessRole.findMany({
    where: { companyId: company.id, deletedAt: null },
    orderBy: { code: 'asc' },
  });
  return res.json({ data: { roles } });
});

businessRouter.post('/roles', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z
    .object({
      code: z.string().min(1).max(80),
      name: z.string().min(1),
      description: z.string().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_ROLE', message: 'Rol invalido.' } });
  }
  const role = await prisma.businessRole.upsert({
    where: { companyId_code: { companyId: company.id, code: parsed.data.code } },
    create: { companyId: company.id, ...parsed.data },
    update: { name: parsed.data.name, description: parsed.data.description, deletedAt: null },
  });
  return res.status(201).json({ data: { role } });
});

businessRouter.post('/users/:userId/roles', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z.object({ roleId: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_ROLE_ASSIGNMENT', message: 'Asignacion invalida.' } });
  }
  const assignment = await prisma.businessUserRole.upsert({
    where: {
      companyId_userId_roleId: {
        companyId: company.id,
        userId: paramValue(req.params.userId),
        roleId: parsed.data.roleId,
      },
    },
    create: { companyId: company.id, userId: paramValue(req.params.userId), roleId: parsed.data.roleId },
    update: { deletedAt: null },
  });
  return res.status(201).json({ data: { assignment } });
});

businessRouter.post('/permissions', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z
    .object({
      module: z.string().min(1),
      actions: z.array(z.string().min(1)).min(1),
      userId: z.string().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success || !permissionDomainSet.has(normalizeModule(parsed.data.module))) {
    return res.status(400).json({ error: { code: 'INVALID_PERMISSION', message: 'Permiso invalido.' } });
  }
  const module = normalizeModule(parsed.data.module);
  const existingPermission = await prisma.permission.findFirst({
    where: { companyId: company.id, userId: parsed.data.userId ?? null, module },
  });
  const permission = existingPermission
    ? await prisma.permission.update({
        where: { id: existingPermission.id },
        data: { actions: parsed.data.actions, deletedAt: null },
      })
    : await prisma.permission.create({
        data: {
          companyId: company.id,
          userId: parsed.data.userId ?? null,
          module,
          actions: parsed.data.actions,
        },
      });
  return res.status(201).json({ data: { permission } });
});

businessRouter.post('/roles/:roleId/permissions', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z.object({ permissionId: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_PERMISSION_ASSIGNMENT', message: 'Asignacion invalida.' } });
  }
  const rolePermission = await prisma.businessRolePermission.upsert({
    where: {
      companyId_roleId_permissionId: {
        companyId: company.id,
        roleId: paramValue(req.params.roleId),
        permissionId: parsed.data.permissionId,
      },
    },
    create: { companyId: company.id, roleId: paramValue(req.params.roleId), permissionId: parsed.data.permissionId },
    update: { deletedAt: null },
  });
  return res.status(201).json({ data: { rolePermission } });
});

businessRouter.get('/company-profile', requirePermission('configuration', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const profile = await prisma.companyProfile.upsert({
    where: { companyId: company.id },
    create: { companyId: company.id, name: company.name },
    update: {},
  });
  return res.json({ data: { profile: sanitizeProfile(profile) } });
});

businessRouter.put('/company-profile', requirePermission('configuration', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z
    .object({
      name: z.string().min(1),
      phone: z.string().nullable().optional(),
      address: z.string().nullable().optional(),
      logoRemoteUrl: z.string().url().nullable().optional(),
      logoUploadStatus: z.string().nullable().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_COMPANY_PROFILE', message: 'Perfil invalido.' } });
  }
  const profile = await prisma.companyProfile.upsert({
    where: { companyId: company.id },
    create: { companyId: company.id, ...parsed.data },
    update: { ...parsed.data, logoLocalPath: null },
  });
  await prisma.company.update({ where: { id: company.id }, data: { name: parsed.data.name } });
  return res.json({ data: { profile: sanitizeProfile(profile) } });
});

businessRouter.get('/financial-parameters', requirePermission('configuration', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parameters = await financialParameters(company.id);
  return res.json({ data: { parameters } });
});

businessRouter.put('/financial-parameters', requirePermission('configuration', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = z
    .object({
      initialPercentage: z.number().min(0).max(100).nullable().optional(),
      monthlyInterestRate: z.number().min(0).max(100).nullable().optional(),
      installmentCount: z.number().int().min(1).max(600).nullable().optional(),
      currencySymbol: z.string().max(12).nullable().optional(),
      decimalPlaces: z.number().int().min(0).max(6).nullable().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_FINANCIAL_PARAMETERS', message: 'Parametros invalidos.' } });
  }
  const parameters = await prisma.financialParameters.upsert({
    where: { companyId: company.id },
    create: { companyId: company.id, ...parsed.data },
    update: parsed.data,
  });
  return res.json({ data: { parameters } });
});

businessRouter.get('/business-config', requirePermission('configuration', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const items = await prisma.businessConfiguration.findMany({
    where: { companyId: company.id, deletedAt: null },
    orderBy: { key: 'asc' },
  });
  return res.json({ data: { items } });
});

businessRouter.put('/business-config/:key', requirePermission('configuration', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const key = paramValue(req.params.key).trim();
  if (!allowedBusinessConfigKeys.has(key)) {
    return res.status(400).json({ error: { code: 'BUSINESS_CONFIG_KEY_NOT_ALLOWED', message: 'Configuracion no permitida.' } });
  }
  const parsed = z
    .object({
      value: z.string().nullable().optional(),
      valueJson: z.any().optional(),
      description: z.string().nullable().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_BUSINESS_CONFIG', message: 'Configuracion invalida.' } });
  }
  const item = await prisma.businessConfiguration.upsert({
    where: { companyId_key: { companyId: company.id, key } },
    create: { companyId: company.id, key, ...parsed.data },
    update: { ...parsed.data, deletedAt: null },
  });
  return res.json({ data: { item } });
});

async function financialParameters(companyId: string) {
  return prisma.financialParameters.upsert({
    where: { companyId },
    create: {
      companyId,
      initialPercentage: 20,
      monthlyInterestRate: 1,
      installmentCount: 12,
      currencySymbol: 'RD$',
      decimalPlaces: 2,
    },
    update: {},
  });
}

function sanitizeProfile<T extends { logoLocalPath?: string | null }>(profile: T) {
  return { ...profile, logoLocalPath: null };
}

function normalizeModule(module: string) {
  return module === 'products' ? 'lots' : module;
}

function paramValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value ?? '';
}
