import { Router } from 'express';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';

export const ownerRouter = Router();

ownerRouter.get('/dashboard', async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const where = { companyId: company.id, deletedAt: null };
  const [
    clients,
    sellers,
    lots,
    sales,
    installments,
    payments,
    saleTotals,
    paymentTotals,
    lastBatch,
  ] = await Promise.all([
    prisma.client.count({ where }),
    prisma.seller.count({ where }),
    prisma.lot.count({ where }),
    prisma.sale.count({ where }),
    prisma.installment.count({ where }),
    prisma.payment.count({ where }),
    prisma.sale.aggregate({
      where,
      _sum: { total: true, balance: true },
    }),
    prisma.payment.aggregate({
      where,
      _sum: { amount: true },
    }),
    prisma.syncBatch.findFirst({
      where: { companyId: company.id },
      orderBy: { createdAt: 'desc' },
    }),
  ]);

  return res.json({
    data: {
      company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
      counts: { clients, sellers, lots, sales, installments, payments },
      totals: {
        sold: saleTotals._sum.total?.toString() ?? '0',
        balance: saleTotals._sum.balance?.toString() ?? '0',
        paid: paymentTotals._sum.amount?.toString() ?? '0',
      },
      lastSync: lastBatch,
      serverTime: new Date().toISOString(),
    },
  });
});

ownerRouter.get('/clients', async (req, res) => list(req, res, 'client'));
ownerRouter.get('/sellers', async (req, res) => list(req, res, 'seller'));
ownerRouter.get('/lots', async (req, res) => list(req, res, 'lot'));
ownerRouter.get('/solares', async (req, res) => list(req, res, 'lot'));
ownerRouter.get('/sales', async (req, res) => list(req, res, 'sale'));
ownerRouter.get('/ventas', async (req, res) => list(req, res, 'sale'));
ownerRouter.get('/installments', async (req, res) => list(req, res, 'installment'));
ownerRouter.get('/cuotas', async (req, res) => list(req, res, 'installment'));
ownerRouter.get('/payments', async (req, res) => list(req, res, 'payment'));
ownerRouter.get('/pagos', async (req, res) => list(req, res, 'payment'));

ownerRouter.get('/sync-status', async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const batches = await prisma.syncBatch.findMany({
    where: { companyId: company.id },
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  return res.json({
    data: {
      company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
      batches,
      serverTime: new Date().toISOString(),
    },
  });
});

async function list(
  req: any,
  res: any,
  model: 'client' | 'seller' | 'lot' | 'sale' | 'installment' | 'payment',
) {
  const page = Math.max(Number(req.query.page ?? 1), 1);
  const pageSize = Math.min(Math.max(Number(req.query.pageSize ?? 50), 1), 200);
  const includeDeleted = String(req.query.includeDeleted ?? 'false') === 'true';
  const skip = (page - 1) * pageSize;
  const delegate = prisma[model] as any;
  const company = await resolveCompanyForRequest(req);
  const where = includeDeleted
    ? { companyId: company.id }
    : { companyId: company.id, deletedAt: null };

  const [items, total] = await Promise.all([
    delegate.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      skip,
      take: pageSize,
    }),
    delegate.count({ where }),
  ]);

  return res.json({
    data: {
      company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
      items,
      page,
      pageSize,
      total,
    },
  });
}
