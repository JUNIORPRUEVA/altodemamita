import { Router } from 'express';
import { authGuard } from '../auth';
import { prisma } from '../prisma';

export const ownerRouter = Router();

ownerRouter.use(authGuard);

ownerRouter.get('/dashboard', async (_req, res) => {
  const [clients, sellers, lots, sales, payments, saleTotals, paymentTotals, lastBatch] =
    await Promise.all([
      prisma.client.count({ where: { deletedAt: null } }),
      prisma.seller.count({ where: { deletedAt: null } }),
      prisma.lot.count({ where: { deletedAt: null } }),
      prisma.sale.count({ where: { deletedAt: null } }),
      prisma.payment.count({ where: { deletedAt: null } }),
      prisma.sale.aggregate({ where: { deletedAt: null }, _sum: { total: true, balance: true } }),
      prisma.payment.aggregate({ where: { deletedAt: null }, _sum: { amount: true } }),
      prisma.syncBatch.findFirst({ orderBy: { createdAt: 'desc' } }),
    ]);

  return res.json({
    data: {
      counts: { clients, sellers, lots, sales, payments },
      totals: {
        sold: saleTotals._sum.total ?? 0,
        balance: saleTotals._sum.balance ?? 0,
        paid: paymentTotals._sum.amount ?? 0,
      },
      lastSync: lastBatch,
    },
  });
});

ownerRouter.get('/clients', async (req, res) => list(req, res, 'client'));
ownerRouter.get('/sellers', async (req, res) => list(req, res, 'seller'));
ownerRouter.get('/lots', async (req, res) => list(req, res, 'lot'));
ownerRouter.get('/sales', async (req, res) => list(req, res, 'sale'));
ownerRouter.get('/payments', async (req, res) => list(req, res, 'payment'));

ownerRouter.get('/sync-status', async (_req, res) => {
  const batches = await prisma.syncBatch.findMany({
    orderBy: { createdAt: 'desc' },
    take: 20,
  });
  return res.json({ data: { batches } });
});

async function list(req: any, res: any, model: 'client' | 'seller' | 'lot' | 'sale' | 'payment') {
  const page = Math.max(Number(req.query.page ?? 1), 1);
  const pageSize = Math.min(Math.max(Number(req.query.pageSize ?? 50), 1), 200);
  const skip = (page - 1) * pageSize;
  const delegate = prisma[model] as any;
  const where = { deletedAt: null };

  const [items, total] = await Promise.all([
    delegate.findMany({ where, orderBy: { updatedAt: 'desc' }, skip, take: pageSize }),
    delegate.count({ where }),
  ]);

  return res.json({ data: { items, page, pageSize, total } });
}
