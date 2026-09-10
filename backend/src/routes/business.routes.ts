import { randomUUID } from 'crypto';
import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { authGuard } from '../auth';
import { resolveCompanyForRequest } from '../companyIdentity';
import { hashPassword } from '../password';
import { prisma } from '../prisma';
import { permissionDomains, requirePermission } from '../rbac';
import { authoritativeErrorResponse } from '../services/authoritativeErrors.service';
import { AuthoritativeSaleService } from '../services/authoritativeSale.service';

export const businessRouter = Router();

const authoritativeSales = new AuthoritativeSaleService(prisma);
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

businessRouter.get('/clients', requirePermission('clients', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const { page, pageSize, skip, search } = listQuery(req.query);
  const where: Prisma.ClientWhereInput = {
    companyId: company.id,
    deletedAt: null,
    ...(search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { document: { contains: search, mode: 'insensitive' } },
            { phone: { contains: search, mode: 'insensitive' } },
            { address: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const [items, total] = await Promise.all([
    prisma.client.findMany({ where, orderBy: { name: 'asc' }, skip, take: pageSize }),
    prisma.client.count({ where }),
  ]);
  return res.json({ data: { items: items.map(clientDto), total, page, pageSize } });
});

businessRouter.post('/clients', requirePermission('clients', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = clientSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_CLIENT', message: 'Cliente invalido.' } });
  }
  const duplicate = await findActiveClientDocument(company.id, parsed.data.document);
  if (duplicate) {
    return res.status(409).json({ error: { code: 'CLIENT_DOCUMENT_EXISTS', message: 'Ya existe un cliente activo con esta cedula.' } });
  }
  const client = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: parsed.data.syncId ?? newSyncId('client'),
      name: parsed.data.name.trim(),
      document: parsed.data.document.trim(),
      phone: cleanNullable(parsed.data.phone),
      address: cleanNullable(parsed.data.address),
      raw: parsed.data.raw ?? {},
    },
  });
  return res.status(201).json({ data: { client: clientDto(client) } });
});

businessRouter.patch('/clients/:clientId', requirePermission('clients', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const clientId = paramValue(req.params.clientId);
  const parsed = clientSchema.partial().safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_CLIENT', message: 'Cliente invalido.' } });
  }
  const existing = await prisma.client.findFirst({ where: { id: clientId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'CLIENT_NOT_FOUND', message: 'El cliente no existe.' } });
  }
  if (parsed.data.document) {
    const duplicate = await findActiveClientDocument(company.id, parsed.data.document, existing.id);
    if (duplicate) {
      return res.status(409).json({ error: { code: 'CLIENT_DOCUMENT_EXISTS', message: 'Ya existe un cliente activo con esta cedula.' } });
    }
  }
  const client = await prisma.client.update({
    where: { id: existing.id },
    data: {
      name: parsed.data.name?.trim(),
      document: parsed.data.document?.trim(),
      phone: cleanNullable(parsed.data.phone),
      address: cleanNullable(parsed.data.address),
      raw: parsed.data.raw,
      version: { increment: 1 },
    },
  });
  return res.json({ data: { client: clientDto(client) } });
});

businessRouter.delete('/clients/:clientId', requirePermission('clients', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const clientId = paramValue(req.params.clientId);
  const existing = await prisma.client.findFirst({ where: { id: clientId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'CLIENT_NOT_FOUND', message: 'El cliente no existe.' } });
  }
  const relatedSale = await prisma.sale.findFirst({
    where: { companyId: company.id, clientId: existing.id },
    select: { id: true },
  });
  if (relatedSale) {
    return res.status(409).json({ error: {
      code: 'CLIENT_HAS_SALES',
      message: 'No puedes eliminar este cliente porque tiene ventas relacionadas. Puedes editar sus datos, pero no eliminarlo mientras exista historial de ventas.',
    } });
  }
  const now = new Date();
  const client = await prisma.client.update({
    where: { id: existing.id },
    data: { deletedAt: now, document: deletedDocument(existing.document, existing.id), version: { increment: 1 } },
  });
  return res.json({ data: { client: clientDto(client) } });
});

businessRouter.get('/sellers', requirePermission('sellers', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const { page, pageSize, skip, search } = listQuery(req.query);
  const where: Prisma.SellerWhereInput = {
    companyId: company.id,
    deletedAt: null,
    ...(search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { document: { contains: search, mode: 'insensitive' } },
            { phone: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const [items, total] = await Promise.all([
    prisma.seller.findMany({ where, orderBy: { name: 'asc' }, skip, take: pageSize }),
    prisma.seller.count({ where }),
  ]);
  return res.json({ data: { items: items.map(sellerDto), total, page, pageSize } });
});

businessRouter.post('/sellers', requirePermission('sellers', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = sellerSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_SELLER', message: 'Vendedor invalido.' } });
  }
  const duplicate = await findActiveSellerDocument(company.id, parsed.data.document);
  if (duplicate) {
    return res.status(409).json({ error: { code: 'SELLER_DOCUMENT_EXISTS', message: 'Ya existe un vendedor activo con esta cedula.' } });
  }
  const seller = await prisma.seller.create({
    data: {
      companyId: company.id,
      syncId: parsed.data.syncId ?? newSyncId('seller'),
      name: parsed.data.name.trim(),
      document: cleanNullable(parsed.data.document),
      phone: cleanNullable(parsed.data.phone),
      active: parsed.data.active ?? true,
      raw: parsed.data.raw ?? {},
    },
  });
  return res.status(201).json({ data: { seller: sellerDto(seller) } });
});

businessRouter.patch('/sellers/:sellerId', requirePermission('sellers', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const sellerId = paramValue(req.params.sellerId);
  const parsed = sellerSchema.partial().safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_SELLER', message: 'Vendedor invalido.' } });
  }
  const existing = await prisma.seller.findFirst({ where: { id: sellerId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'SELLER_NOT_FOUND', message: 'El vendedor no existe.' } });
  }
  if (parsed.data.document) {
    const duplicate = await findActiveSellerDocument(company.id, parsed.data.document, existing.id);
    if (duplicate) {
      return res.status(409).json({ error: { code: 'SELLER_DOCUMENT_EXISTS', message: 'Ya existe un vendedor activo con esta cedula.' } });
    }
  }
  const seller = await prisma.seller.update({
    where: { id: existing.id },
    data: {
      name: parsed.data.name?.trim(),
      document: cleanNullable(parsed.data.document),
      phone: cleanNullable(parsed.data.phone),
      active: parsed.data.active,
      raw: parsed.data.raw,
      version: { increment: 1 },
    },
  });
  return res.json({ data: { seller: sellerDto(seller) } });
});

businessRouter.delete('/sellers/:sellerId', requirePermission('sellers', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const sellerId = paramValue(req.params.sellerId);
  const existing = await prisma.seller.findFirst({ where: { id: sellerId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'SELLER_NOT_FOUND', message: 'El vendedor no existe.' } });
  }
  const activeSale = await prisma.sale.findFirst({
    where: { companyId: company.id, sellerId: existing.id, deletedAt: null, NOT: { status: 'cancelada' } },
    select: { id: true },
  });
  if (activeSale) {
    return res.status(409).json({ error: { code: 'SELLER_HAS_ACTIVE_SALE', message: 'No puedes eliminar este vendedor porque tiene una venta activa relacionada.' } });
  }
  const seller = await prisma.seller.update({
    where: { id: existing.id },
    data: { active: false, deletedAt: new Date(), document: deletedDocument(existing.document, existing.id), version: { increment: 1 } },
  });
  return res.json({ data: { seller: sellerDto(seller) } });
});

businessRouter.get('/lots', requirePermission('lots', 'read'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const { page, pageSize, skip, search } = listQuery(req.query);
  const status = stringQuery(req.query.status);
  const where: Prisma.LotWhereInput = {
    companyId: company.id,
    deletedAt: null,
    ...(status ? { status } : {}),
    ...(search
      ? {
          OR: [
            { block: { contains: search, mode: 'insensitive' } },
            { number: { contains: search, mode: 'insensitive' } },
            { status: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {}),
  };
  const [items, total] = await Promise.all([
    prisma.lot.findMany({ where, orderBy: [{ block: 'asc' }, { number: 'asc' }], skip, take: pageSize }),
    prisma.lot.count({ where }),
  ]);
  return res.json({ data: { items: items.map(lotDto), total, page, pageSize } });
});

businessRouter.post('/lots', requirePermission('lots', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const parsed = lotSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_LOT', message: 'Solar invalido.' } });
  }
  const duplicate = await findActiveLot(company.id, parsed.data.block, parsed.data.number);
  if (duplicate) {
    return res.status(409).json({ error: { code: 'LOT_EXISTS', message: 'Ya existe un solar activo con esta manzana y numero.' } });
  }
  const lot = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: parsed.data.syncId ?? newSyncId('product'),
      block: parsed.data.block.trim(),
      number: parsed.data.number.trim(),
      status: parsed.data.status ?? 'disponible',
      area: decimal(parsed.data.area),
      price: decimal(parsed.data.price),
      raw: parsed.data.raw ?? {},
    },
  });
  return res.status(201).json({ data: { lot: lotDto(lot) } });
});

businessRouter.patch('/lots/:lotId', requirePermission('lots', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const lotId = paramValue(req.params.lotId);
  const parsed = lotSchema.partial().safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_LOT', message: 'Solar invalido.' } });
  }
  const existing = await prisma.lot.findFirst({ where: { id: lotId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'LOT_NOT_FOUND', message: 'El solar no existe.' } });
  }
  const nextBlock = parsed.data.block ?? existing.block ?? '';
  const nextNumber = parsed.data.number ?? existing.number ?? '';
  const duplicate = await findActiveLot(company.id, nextBlock, nextNumber, existing.id);
  if (duplicate) {
    return res.status(409).json({ error: { code: 'LOT_EXISTS', message: 'Ya existe un solar activo con esta manzana y numero.' } });
  }
  const lot = await prisma.lot.update({
    where: { id: existing.id },
    data: {
      block: parsed.data.block?.trim(),
      number: parsed.data.number?.trim(),
      status: parsed.data.status,
      area: parsed.data.area == null ? undefined : decimal(parsed.data.area),
      price: parsed.data.price == null ? undefined : decimal(parsed.data.price),
      raw: parsed.data.raw,
      version: { increment: 1 },
    },
  });
  return res.json({ data: { lot: lotDto(lot) } });
});

businessRouter.delete('/lots/:lotId', requirePermission('lots', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const lotId = paramValue(req.params.lotId);
  const existing = await prisma.lot.findFirst({ where: { id: lotId, companyId: company.id, deletedAt: null } });
  if (!existing) {
    return res.status(404).json({ error: { code: 'LOT_NOT_FOUND', message: 'El solar no existe.' } });
  }
  const activeSale = await prisma.sale.findFirst({
    where: { companyId: company.id, lotId: existing.id, deletedAt: null, NOT: { status: 'cancelada' } },
    select: { id: true, syncId: true },
  });
  if (activeSale) {
    return res.status(409).json({ error: { code: 'LOT_HAS_ACTIVE_SALE', message: 'No puedes eliminar este solar porque tiene una venta activa.' } });
  }
  const lot = await prisma.lot.update({
    where: { id: existing.id },
    data: { deletedAt: new Date(), version: { increment: 1 } },
  });
  return res.json({ data: { lot: lotDto(lot) } });
});

businessRouter.patch('/sales/:saleId', requirePermission('sales', 'write'), async (req, res) => {
  try {
    const company = await resolveCompanyForRequest(req);
    const result = await authoritativeSales.updateSale({
      ...(req.body as Record<string, never>),
      companyId: company.id,
      operatorUserId: req.user?.id ?? '',
      saleId: paramValue(req.params.saleId),
      idempotencyKey: idempotencyKey(req) ?? '',
    });
    return res.status(result.replayed ? 200 : 200).json({
      data: result.response,
      idempotentReplay: result.replayed,
    });
  } catch (error) {
    const response = authoritativeErrorResponse(error);
    return res.status(response.status).json(response.body);
  }
});

businessRouter.patch('/users/:userId', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const userId = paramValue(req.params.userId);
  const parsed = z
    .object({
      email: z.string().email().optional(),
      name: z.string().min(1).optional(),
      fullName: z.string().min(1).optional(),
      role: z.enum(['OWNER', 'TECH']).optional(),
      roleCode: z.string().optional(),
      active: z.boolean().optional(),
      isActive: z.boolean().optional(),
      password: z.string().min(8).optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { code: 'INVALID_USER', message: 'Usuario invalido.' } });
  }

  const existing = await prisma.user.findFirst({
    where: {
      id: userId,
      deletedAt: null,
      OR: [{ companyId: company.id }, { companyId: null }],
    },
    select: { id: true, email: true, name: true, role: true, active: true, passwordHash: true, companyId: true },
  });
  if (!existing) {
    return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'El usuario no existe.' } });
  }

  const nextActive = parsed.data.active ?? parsed.data.isActive ?? existing.active;
  const nextRole = normalizeUserRole(parsed.data.role ?? parsed.data.roleCode) ?? existing.role;
  if (isSelfDeactivation(req.user?.id, existing.id, nextActive)) {
    return res.status(409).json({
      error: {
        code: 'CANNOT_DEACTIVATE_SELF',
        message: 'No puedes desactivar tu propio usuario.',
      },
    });
  }
  if (isOwnerRemovalAttempt(existing.role, nextRole, nextActive)) {
    const activeOwners = await countActiveOwners(company.id, existing.id);
    if (activeOwners === 0) {
      return res.status(409).json({
        error: {
          code: 'LAST_OWNER_REQUIRED',
          message: 'Debe existir al menos un OWNER activo.',
        },
      });
    }
  }

  const data = {
    email: parsed.data.email?.trim().toLowerCase(),
    name: (parsed.data.name ?? parsed.data.fullName)?.trim(),
    role: nextRole,
    active: nextActive,
    passwordHash: parsed.data.password ? await hashPassword(parsed.data.password) : undefined,
    passwordUpdatedAt: parsed.data.password ? new Date() : undefined,
    version: { increment: 1 },
  };
  const user = await prisma.user.update({
    where: { id: existing.id },
    data,
    select: { id: true, email: true, name: true, role: true, active: true, localRole: true, phone: true, companyId: true },
  });
  return res.json({ data: { user } });
});

businessRouter.delete('/users/:userId', requirePermission('users', 'write'), async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const userId = paramValue(req.params.userId);
  const existing = await prisma.user.findFirst({
    where: {
      id: userId,
      deletedAt: null,
      OR: [{ companyId: company.id }, { companyId: null }],
    },
    select: { id: true, role: true, active: true },
  });
  if (!existing) {
    return res.status(404).json({ error: { code: 'USER_NOT_FOUND', message: 'El usuario no existe.' } });
  }
  if (req.user?.id === existing.id) {
    return res.status(409).json({
      error: {
        code: 'CANNOT_DELETE_SELF',
        message: 'No puedes eliminar tu propio usuario.',
      },
    });
  }
  if (existing.role === 'OWNER' && existing.active) {
    const activeOwners = await countActiveOwners(company.id, existing.id);
    if (activeOwners === 0) {
      return res.status(409).json({
        error: {
          code: 'LAST_OWNER_REQUIRED',
          message: 'Debe existir al menos un OWNER activo.',
        },
      });
    }
  }

  const [operatedSales, receivedPayments, annulledPayments] = await Promise.all([
    prisma.sale.count({ where: { companyId: company.id, operatorUserId: existing.id } }),
    prisma.payment.count({ where: { companyId: company.id, receivedByUserId: existing.id } }),
    prisma.payment.count({ where: { companyId: company.id, annulledByUserId: existing.id } }),
  ]);
  if (hasBlockingUserHistoryForDelete({ operatedSales, receivedPayments, annulledPayments })) {
    return res.status(409).json({
      error: {
        code: 'USER_HAS_HISTORY',
        message: 'No se puede eliminar este usuario porque tiene informacion historica relacionada.',
      },
    });
  }

  try {
    await prisma.$transaction(async (tx) => {
      await tx.permission.deleteMany({ where: { companyId: company.id, userId: existing.id } });
      await tx.businessUserRole.deleteMany({ where: { companyId: company.id, userId: existing.id } });
      await tx.user.delete({ where: { id: existing.id } });
    });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') {
      return res.status(409).json({
        error: {
          code: 'USER_HAS_HISTORY',
          message: 'No se puede eliminar este usuario porque tiene informacion historica relacionada.',
        },
      });
    }
    throw error;
  }
  return res.json({ data: { deleted: true, userId: existing.id } });
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

const clientSchema = z.object({
  syncId: z.string().min(1).optional(),
  name: z.string().min(1),
  document: z.string().min(1),
  phone: z.string().nullable().optional(),
  address: z.string().nullable().optional(),
  raw: z.any().optional(),
});

const sellerSchema = z.object({
  syncId: z.string().min(1).optional(),
  name: z.string().min(1),
  document: z.string().nullable().optional(),
  phone: z.string().nullable().optional(),
  active: z.boolean().optional(),
  raw: z.any().optional(),
});

const lotSchema = z.object({
  syncId: z.string().min(1).optional(),
  block: z.string().min(1),
  number: z.string().min(1),
  status: z.enum(['disponible', 'reservado', 'vendido']).optional(),
  area: z.coerce.number().min(0),
  price: z.coerce.number().min(0),
  raw: z.any().optional(),
});

function listQuery(query: Record<string, unknown>) {
  const page = Math.max(Number(stringQuery(query.page) ?? 1), 1);
  const pageSize = Math.min(Math.max(Number(stringQuery(query.limit) ?? stringQuery(query.pageSize) ?? 100), 1), 500);
  return {
    page,
    pageSize,
    skip: (page - 1) * pageSize,
    search: stringQuery(query.search),
  };
}

function stringQuery(value: unknown) {
  const raw = Array.isArray(value) ? value[0] : value;
  if (typeof raw !== 'string') return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function cleanNullable(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function newSyncId(prefix: string) {
  return `${prefix}-${randomUUID()}`;
}

function decimal(value: number) {
  return new Prisma.Decimal(value.toString());
}

function numeric(value: unknown) {
  if (value instanceof Prisma.Decimal) {
    return value.toNumber();
  }
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function clientDto(client: {
  id: string;
  syncId: string;
  name: string;
  document: string | null;
  phone: string | null;
  address: string | null;
  version: number;
  deletedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: client.id,
    syncId: client.syncId,
    sync_id: client.syncId,
    name: client.name,
    full_name: client.name,
    document: client.document ?? '',
    documentId: client.document ?? '',
    document_id: client.document ?? '',
    phone: client.phone,
    address: client.address,
    version: client.version,
    deletedAt: client.deletedAt?.toISOString() ?? null,
    deleted_at: client.deletedAt?.toISOString() ?? null,
    createdAt: client.createdAt.toISOString(),
    created_at: client.createdAt.toISOString(),
    updatedAt: client.updatedAt.toISOString(),
    updated_at: client.updatedAt.toISOString(),
  };
}

function sellerDto(seller: {
  id: string;
  syncId: string;
  name: string;
  document: string | null;
  phone: string | null;
  active: boolean;
  version: number;
  deletedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: seller.id,
    syncId: seller.syncId,
    sync_id: seller.syncId,
    name: seller.name,
    full_name: seller.name,
    document: seller.document,
    documentId: seller.document,
    document_id: seller.document,
    phone: seller.phone,
    active: seller.active,
    version: seller.version,
    deletedAt: seller.deletedAt?.toISOString() ?? null,
    deleted_at: seller.deletedAt?.toISOString() ?? null,
    createdAt: seller.createdAt.toISOString(),
    created_at: seller.createdAt.toISOString(),
    updatedAt: seller.updatedAt.toISOString(),
    updated_at: seller.updatedAt.toISOString(),
  };
}

function lotDto(lot: {
  id: string;
  syncId: string;
  block: string | null;
  number: string | null;
  status: string | null;
  area: unknown;
  price: unknown;
  version: number;
  deletedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: lot.id,
    syncId: lot.syncId,
    sync_id: lot.syncId,
    block: lot.block ?? '',
    blockNumber: lot.block ?? '',
    block_number: lot.block ?? '',
    number: lot.number ?? '',
    lotNumber: lot.number ?? '',
    lot_number: lot.number ?? '',
    status: lot.status,
    area: numeric(lot.area),
    price: numeric(lot.price),
    pricePerSquareMeter: numeric(lot.price),
    price_per_square_meter: numeric(lot.price),
    version: lot.version,
    deletedAt: lot.deletedAt?.toISOString() ?? null,
    deleted_at: lot.deletedAt?.toISOString() ?? null,
    createdAt: lot.createdAt.toISOString(),
    created_at: lot.createdAt.toISOString(),
    updatedAt: lot.updatedAt.toISOString(),
    updated_at: lot.updatedAt.toISOString(),
  };
}

async function findActiveClientDocument(companyId: string, document: string, excludingId?: string) {
  return prisma.client.findFirst({
    where: {
      companyId,
      deletedAt: null,
      document: { equals: document.trim(), mode: 'insensitive' },
      ...(excludingId ? { id: { not: excludingId } } : {}),
    },
    select: { id: true },
  });
}

async function findActiveSellerDocument(companyId: string, document: string | null | undefined, excludingId?: string) {
  const normalized = document?.trim();
  if (!normalized) return null;
  return prisma.seller.findFirst({
    where: {
      companyId,
      deletedAt: null,
      document: { equals: normalized, mode: 'insensitive' },
      ...(excludingId ? { id: { not: excludingId } } : {}),
    },
    select: { id: true },
  });
}

async function findActiveLot(companyId: string, block: string, number: string, excludingId?: string) {
  return prisma.lot.findFirst({
    where: {
      companyId,
      deletedAt: null,
      block: { equals: block.trim(), mode: 'insensitive' },
      number: { equals: number.trim(), mode: 'insensitive' },
      ...(excludingId ? { id: { not: excludingId } } : {}),
    },
    select: { id: true },
  });
}

function deletedDocument(document: string | null, id: string) {
  const normalized = document?.trim() ?? '';
  return normalized.startsWith('__DELETED__') ? normalized : `__DELETED__${id}`;
}

function normalizeModule(module: string) {
  return module === 'products' ? 'lots' : module;
}

function paramValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value ?? '';
}

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

function normalizeUserRole(value: string | undefined) {
  const normalized = value?.trim().toUpperCase();
  if (!normalized) return undefined;
  if (['OWNER', 'ADMIN', 'SUPER_ADMIN'].includes(normalized)) return 'OWNER';
  return 'TECH';
}

export function normalizeBusinessUserRoleForTest(value: string | undefined) {
  return normalizeUserRole(value);
}

export function isSelfDeactivation(
  actorUserId: string | undefined,
  targetUserId: string,
  nextActive: boolean,
) {
  return actorUserId === targetUserId && !nextActive;
}

export function isOwnerRemovalAttempt(
  currentRole: 'OWNER' | 'TECH',
  nextRole: 'OWNER' | 'TECH',
  nextActive: boolean,
) {
  return currentRole === 'OWNER' && (!nextActive || nextRole !== 'OWNER');
}

export function hasBlockingUserHistoryForDelete(counts: {
  operatedSales: number;
  receivedPayments: number;
  annulledPayments: number;
}) {
  return counts.operatedSales > 0 || counts.receivedPayments > 0 || counts.annulledPayments > 0;
}

async function countActiveOwners(companyId: string, excludingUserId: string) {
  return prisma.user.count({
    where: {
      id: { not: excludingUserId },
      role: 'OWNER',
      active: true,
      deletedAt: null,
      OR: [{ companyId }, { companyId: null }],
    },
  });
}
