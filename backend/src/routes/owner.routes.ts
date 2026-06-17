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
ownerRouter.get('/sales', listSales);
ownerRouter.get('/ventas', listSales);
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

async function listSales(req: any, res: any) {
  const page = Math.max(Number(req.query.page ?? 1), 1);
  const pageSize = Math.min(Math.max(Number(req.query.pageSize ?? 50), 1), 200);
  const includeDeleted = String(req.query.includeDeleted ?? 'false') === 'true';
  const skip = (page - 1) * pageSize;
  const company = await resolveCompanyForRequest(req);
  const where = includeDeleted
    ? { companyId: company.id }
    : { companyId: company.id, deletedAt: null };

  const [sales, total] = await Promise.all([
    prisma.sale.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      skip,
      take: pageSize,
    }),
    prisma.sale.count({ where }),
  ]);

  const clientSyncIds = uniqueSyncIds(sales.map((sale) => sale.clientSyncId));
  const lotSyncIds = uniqueSyncIds(sales.map((sale) => sale.lotSyncId));
  const sellerSyncIds = uniqueSyncIds(sales.map((sale) => sale.sellerSyncId));

  const [clients, lots, sellers] = await Promise.all([
    prisma.client.findMany({
      where: { companyId: company.id, syncId: { in: clientSyncIds } },
    }),
    prisma.lot.findMany({
      where: { companyId: company.id, syncId: { in: lotSyncIds } },
    }),
    prisma.seller.findMany({
      where: { companyId: company.id, syncId: { in: sellerSyncIds } },
    }),
  ]);

  const clientsBySyncId = bySyncId(clients);
  const lotsBySyncId = bySyncId(lots);
  const sellersBySyncId = bySyncId(sellers);

  return res.json({
    data: {
      company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
      items: sales.map((sale) => {
        const client = sale.clientSyncId ? clientsBySyncId.get(sale.clientSyncId) : null;
        const lot = sale.lotSyncId ? lotsBySyncId.get(sale.lotSyncId) : null;
        const seller = sale.sellerSyncId ? sellersBySyncId.get(sale.sellerSyncId) : null;
        return {
          ...sale,
          saleId: sale.id,
          syncId: sale.syncId,
          client: client?.name ?? null,
          cedula: client?.document ?? null,
          clientPhone: client?.phone ?? null,
          clientAddress: client?.address ?? null,
          lot: lot ? lotDisplay(lot) : null,
          lotBlock: lot?.block ?? null,
          lotNumber: lot?.number ?? null,
          seller: seller?.name ?? null,
          sellerDocument: seller?.document ?? null,
          saleDate: sale.saleDate?.toISOString() ?? null,
          total: sale.total?.toString() ?? '0',
          initialPaid: sale.initialPaid?.toString() ?? '0',
          balance: sale.balance?.toString() ?? '0',
          createdAt: sale.createdAt?.toISOString(),
          updatedAt: sale.updatedAt?.toISOString(),
          deletedAt: sale.deletedAt?.toISOString() ?? null,
        };
      }),
      page,
      pageSize,
      total,
    },
  });
}

function uniqueSyncIds(values: Array<string | null>) {
  return [...new Set(values.filter((value): value is string => Boolean(value?.trim())))];
}

function bySyncId<T extends { syncId: string }>(items: T[]) {
  return new Map(items.map((item) => [item.syncId, item]));
}

function lotDisplay(lot: { block: string | null; number: string | null }) {
  const block = lot.block?.trim() ?? '';
  const number = lot.number?.trim() ?? '';
  if (block && number) return `M${block}-S${number}`;
  if (number) return `Solar ${number}`;
  if (block) return `Manzana ${block}`;
  return null;
}
