import { Router } from 'express';
import { authGuard } from '../auth';
import { config } from '../config';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';

export const ownerRouter = Router();

if (!config.ownerReadAllowAnonymous) {
  ownerRouter.use(authGuard);
}

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
ownerRouter.get('/sales/:saleId/payments-context', salePaymentsContext);
ownerRouter.get('/ventas/:saleId/payments-context', salePaymentsContext);
ownerRouter.get('/sales/:saleId', saleDetail);
ownerRouter.get('/ventas/:saleId', saleDetail);
ownerRouter.get('/clients/:clientId', clientDetail);
ownerRouter.get('/clientes/:clientId', clientDetail);
ownerRouter.get('/payments/work-queue', paymentsWorkQueue);
ownerRouter.get('/pagos/work-queue', paymentsWorkQueue);
ownerRouter.get('/payments/sales-search', paymentsSalesSearch);
ownerRouter.get('/pagos/sales-search', paymentsSalesSearch);
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
  const settlementFilter = String(req.query.settlement ?? '').trim().toLowerCase();
  const onlyFullyPaid = settlementFilter === 'fully_paid';
  const skip = (page - 1) * pageSize;
  const company = await resolveCompanyForRequest(req);
  const today = startOfUtcDay(new Date());
  const lotIdFilter = String(req.query.lotId ?? '').trim();
  const baseWhere = lotIdFilter
    ? {
        companyId: company.id,
        deletedAt: null,
        OR: [{ lotId: lotIdFilter }, { lotSyncId: lotIdFilter }],
      }
    : includeDeleted
      ? { companyId: company.id }
      : { companyId: company.id, deletedAt: null };

  // La clasificacion "venta definitiva" es derivada: se pre-filtra en SQL por lo
  // que es verificable en la fila (saldo, inicial, no cancelada) y se confirma
  // despues contra las obligaciones pendientes reales de cada venta.
  const where = onlyFullyPaid
    ? {
        ...baseWhere,
        deletedAt: null,
        NOT: { status: 'cancelada' },
        balance: { lte: SETTLEMENT_TOLERANCE },
        initialPendingAmount: { lte: SETTLEMENT_TOLERANCE },
      }
    : baseWhere;

  const FULLY_PAID_FETCH_CAP = 500;

  const [candidateSales, unfilteredTotal] = await Promise.all([
    prisma.sale.findMany({
      where,
      orderBy: { updatedAt: 'desc' },
      skip: onlyFullyPaid ? 0 : skip,
      take: onlyFullyPaid ? FULLY_PAID_FETCH_CAP : pageSize,
    }),
    onlyFullyPaid ? Promise.resolve(0) : prisma.sale.count({ where }),
  ]);

  const candidateIds = candidateSales.map((sale: any) => sale.id);
  const outstandingBySaleId = new Map<string, number>();
  const overdueInstallmentCountBySaleId = new Map<string, number>();
  if (candidateIds.length > 0) {
    const installmentsForCandidates = await prisma.installment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        saleId: { in: candidateIds },
      },
      select: {
        saleId: true,
        dueDate: true,
        status: true,
        totalAmount: true,
        paidAmount: true,
      },
    });
    for (const installment of installmentsForCandidates as Array<any>) {
      const saleId = installment.saleId;
      if (!saleId) continue;
      const remaining = roundMoney(
        Math.max(
          toNumber(installment.totalAmount) - toNumber(installment.paidAmount),
          0,
        ),
      );
      outstandingBySaleId.set(
        saleId,
        roundMoney((outstandingBySaleId.get(saleId) ?? 0) + remaining),
      );
      if (isOverdueInstallmentObligation(installment, today)) {
        overdueInstallmentCountBySaleId.set(
          saleId,
          (overdueInstallmentCountBySaleId.get(saleId) ?? 0) + 1,
        );
      }
    }
  }

  const settlementBySaleId = new Map<string, SaleSettlement>();
  for (const sale of candidateSales as Array<any>) {
    settlementBySaleId.set(
      sale.id,
      deriveSettlement(sale, outstandingBySaleId.get(sale.id) ?? 0),
    );
  }

  const salesPage = onlyFullyPaid
    ? (candidateSales as Array<any>).filter(
        (sale) => settlementBySaleId.get(sale.id)?.isFullyPaid === true,
      )
    : (candidateSales as Array<any>);
  const total = onlyFullyPaid ? salesPage.length : unfilteredTotal;
  const pageSales = onlyFullyPaid ? salesPage.slice(skip, skip + pageSize) : salesPage;

  const clientSyncIds = uniqueSyncIds(pageSales.map((sale) => sale.clientSyncId));
  const lotSyncIds = uniqueSyncIds(pageSales.map((sale) => sale.lotSyncId));
  const sellerSyncIds = uniqueSyncIds(pageSales.map((sale) => sale.sellerSyncId));

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
      items: pageSales.map((sale) =>
        serializeSaleRow(
          sale,
          clientsBySyncId,
          lotsBySyncId,
          sellersBySyncId,
          settlementBySaleId.get(sale.id),
          overdueInstallmentCountBySaleId.get(sale.id) ?? 0,
        ),
      ),
      page,
      pageSize,
      total,
      settlementFilter: onlyFullyPaid ? 'fully_paid' : null,
    },
  });
}

async function saleDetail(req: any, res: any) {
  const company = await resolveCompanyForRequest(req);
  const saleId = String(req.params.saleId ?? '').trim();

  const sale = await prisma.sale.findFirst({
    where: { id: saleId, companyId: company.id, deletedAt: null },
  });
  if (!sale) {
    return res.status(404).json({
      error: { code: 'SALE_NOT_FOUND', message: 'Venta no encontrada.' },
    });
  }

  const [client, lot, seller, installments, payments] = await Promise.all([
    sale.clientSyncId
      ? prisma.client.findFirst({ where: { companyId: company.id, syncId: sale.clientSyncId } })
      : null,
    sale.lotSyncId
      ? prisma.lot.findFirst({ where: { companyId: company.id, syncId: sale.lotSyncId } })
      : null,
    sale.sellerSyncId
      ? prisma.seller.findFirst({ where: { companyId: company.id, syncId: sale.sellerSyncId } })
      : null,
    prisma.installment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        OR: [{ saleId: sale.id }, { saleSyncId: sale.syncId }],
      },
      orderBy: { installmentNumber: 'asc' },
    }),
    prisma.payment.findMany({
      where: {
        companyId: company.id,
        saleId: sale.id,
        installmentId: null,
        annulledAt: null,
        deletedAt: null,
      },
      orderBy: { paidAt: 'asc' },
    }),
  ]);

  const clientsBySyncId = new Map<string, any>(client ? [[client.syncId, client]] : []);
  const lotsBySyncId = new Map<string, any>(lot ? [[lot.syncId, lot]] : []);
  const sellersBySyncId = new Map<string, any>(seller ? [[seller.syncId, seller]] : []);

  return res.json({
    data: {
      sale: {
        ...serializeSaleRow(
          sale,
          clientsBySyncId,
          lotsBySyncId,
          sellersBySyncId,
          deriveSettlement(sale, outstandingFromInstallments(installments)),
        ),
        installments: installments.map(serializeInstallmentRow),
        payments: payments.map((payment) => ({
          id: payment.id,
          syncId: payment.syncId,
          method: payment.method,
          amount: payment.amount?.toString() ?? '0',
          paidAt: payment.paidAt?.toISOString() ?? null,
          paymentType: payment.paymentType,
        })),
      },
    },
  });
}

async function salePaymentsContext(req: any, res: any) {
  const company = await resolveCompanyForRequest(req);
  const saleId = String(req.params.saleId ?? '').trim();

  const sale = await prisma.sale.findFirst({
    where: { id: saleId, companyId: company.id, deletedAt: null },
  });
  if (!sale) {
    return res.status(404).json({
      error: { code: 'SALE_NOT_FOUND', message: 'Venta no encontrada.' },
    });
  }

  const [client, lot, seller, installments, payments, annulledPayments] = await Promise.all([
    sale.clientSyncId
      ? prisma.client.findFirst({
          where: { companyId: company.id, syncId: sale.clientSyncId },
        })
      : null,
    sale.lotSyncId
      ? prisma.lot.findFirst({
          where: { companyId: company.id, syncId: sale.lotSyncId },
        })
      : null,
    sale.sellerSyncId
      ? prisma.seller.findFirst({
          where: { companyId: company.id, syncId: sale.sellerSyncId },
        })
      : null,
    prisma.installment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        OR: [{ saleId: sale.id }, { saleSyncId: sale.syncId }],
      },
      orderBy: { installmentNumber: 'asc' },
    }),
    prisma.payment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        annulledAt: null,
        OR: [{ saleId: sale.id }, { saleSyncId: sale.syncId }],
      },
      orderBy: { paidAt: 'asc' },
    }),
    prisma.payment.findMany({
      where: {
        companyId: company.id,
        annulledAt: { not: null },
        OR: [{ saleId: sale.id }, { saleSyncId: sale.syncId }],
      },
      orderBy: { annulledAt: 'desc' },
      include: { annulledByUser: { select: { id: true, name: true } } },
    }),
  ]);

  const clientsBySyncId = new Map<string, any>(client ? [[client.syncId, client]] : []);
  const lotsBySyncId = new Map<string, any>(lot ? [[lot.syncId, lot]] : []);
  const sellersBySyncId = new Map<string, any>(seller ? [[seller.syncId, seller]] : []);

  return res.json({
    data: {
      sale: serializeSaleRow(
        sale,
        clientsBySyncId,
        lotsBySyncId,
        sellersBySyncId,
        deriveSettlement(sale, outstandingFromInstallments(installments)),
      ),
      installments: installments.map(serializeInstallmentRow),
      payments: payments.map(serializePaymentRow),
      annulledPayments: annulledPayments.map(serializePaymentRow),
    },
  });
}

async function paymentsWorkQueue(req: any, res: any) {
  const startedAt = Date.now();
  const company = await resolveCompanyForRequest(req);
  const page = Math.max(Number(req.query.page ?? 1), 1);
  const pageSize = Math.min(Math.max(Number(req.query.pageSize ?? 50), 1), 100);
  const state = String(req.query.state ?? 'collectible').trim().toLowerCase();
  const search = String(req.query.search ?? '').trim();
  const skip = (page - 1) * pageSize;
  const today = startOfUtcDay(new Date());

  const saleSearchWhere = await buildPaymentSaleSearchWhere(company.id, search);
  // Una venta saldada ("venta definitiva") deja de ser cobrable: no debe aparecer
  // en la cola operativa de cobro. Su historial de pagos sigue siendo consultable.
  const collectibleSaleFilter = {
    deletedAt: null,
    NOT: { status: 'cancelada' },
    balance: { gt: SETTLEMENT_TOLERANCE },
  };
  const saleFilterForState =
    state === 'paid' || state === 'all'
      ? saleSearchWhere
      : combineSaleFilters(saleSearchWhere, collectibleSaleFilter);
  const saleFilterForCounts = combineSaleFilters(saleSearchWhere, collectibleSaleFilter);
  const where = {
    ...installmentQueueWhere(company.id, state, today),
    ...(saleFilterForState ? { sale: saleFilterForState } : {}),
  };
  const orderBy =
    state === 'paid'
      ? [{ dueDate: 'desc' as const }, { installmentNumber: 'desc' as const }]
      : [{ dueDate: 'asc' as const }, { installmentNumber: 'asc' as const }];

  const [installments, total, overdue, dueToday, pending, partial] = await Promise.all([
    prisma.installment.findMany({
      where,
      include: { sale: true },
      orderBy,
      skip,
      take: pageSize,
    }),
    prisma.installment.count({ where }),
    prisma.installment.count({
      where: {
        ...installmentQueueWhere(company.id, 'overdue', today),
        ...(saleFilterForCounts ? { sale: saleFilterForCounts } : {}),
      },
    }),
    prisma.installment.count({
      where: {
        ...installmentQueueWhere(company.id, 'dueToday', today),
        ...(saleFilterForCounts ? { sale: saleFilterForCounts } : {}),
      },
    }),
    prisma.installment.count({
      where: {
        ...installmentQueueWhere(company.id, 'pending', today),
        ...(saleFilterForCounts ? { sale: saleFilterForCounts } : {}),
      },
    }),
    prisma.installment.count({
      where: {
        ...installmentQueueWhere(company.id, 'partial', today),
        ...(saleFilterForCounts ? { sale: saleFilterForCounts } : {}),
      },
    }),
  ]);

  const sales = installments.map((installment) => installment.sale).filter(Boolean);
  const queueSaleIds = uniqueSyncIds(sales.map((sale: any) => sale.id));
  const queueOutstandingBySaleId = new Map<string, number>();
  if (queueSaleIds.length > 0) {
    const grouped = await prisma.installment.groupBy({
      by: ['saleId'],
      where: { companyId: company.id, deletedAt: null, saleId: { in: queueSaleIds } },
      _sum: { totalAmount: true, paidAmount: true },
    });
    for (const row of grouped as Array<any>) {
      if (!row.saleId) continue;
      queueOutstandingBySaleId.set(
        row.saleId,
        roundMoney(
          Math.max(toNumber(row._sum?.totalAmount) - toNumber(row._sum?.paidAmount), 0),
        ),
      );
    }
  }
  const clientSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.clientSyncId));
  const lotSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.lotSyncId));
  const sellerSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.sellerSyncId));
  const [clients, lots, sellers] = await Promise.all([
    clientSyncIds.length
      ? prisma.client.findMany({ where: { companyId: company.id, syncId: { in: clientSyncIds } } })
      : [],
    lotSyncIds.length
      ? prisma.lot.findMany({ where: { companyId: company.id, syncId: { in: lotSyncIds } } })
      : [],
    sellerSyncIds.length
      ? prisma.seller.findMany({ where: { companyId: company.id, syncId: { in: sellerSyncIds } } })
      : [],
  ]);

  const clientsBySyncId = bySyncId(clients);
  const lotsBySyncId = bySyncId(lots);
  const sellersBySyncId = bySyncId(sellers);

  return res.json({
    data: {
      company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
      items: installments
        .filter((installment) => installment.sale)
        .map((installment) => ({
          sale: serializeSaleRow(
            installment.sale,
            clientsBySyncId,
            lotsBySyncId,
            sellersBySyncId,
            deriveSettlement(
              installment.sale,
              queueOutstandingBySaleId.get(String(installment.sale?.id ?? '')) ?? 0,
            ),
          ),
          installment: serializeInstallmentRow(installment),
        })),
      page,
      pageSize,
      total,
      counts: { overdue, dueToday, pending, partial },
      durationMs: Date.now() - startedAt,
    },
  });
}

/**
 * Terminos de busqueda derivados de lo que el usuario escribe en Pagos.
 *
 * Soporta nombre/cedula/telefono directos, el formato de presentacion de solar
 * ("Mgf-S1212") y su parte numerica ("1212"), de modo que una venta real pueda
 * encontrarse por cualquiera de las formas visibles en el modulo Ventas.
 */
export function paymentSalesSearchTerms(rawQuery: string): string[] {
  const trimmed = rawQuery.trim();
  if (trimmed.length === 0) {
    return [];
  }
  const terms = new Set<string>([trimmed]);
  const digits = trimmed.replace(/\D+/g, '');
  if (digits.length >= 3) {
    terms.add(digits);
  }
  const displayMatch = /^m?([a-z0-9]+)\s*-\s*s?([a-z0-9]+)$/i.exec(trimmed);
  if (displayMatch) {
    terms.add(displayMatch[1]);
    terms.add(displayMatch[2]);
  }
  return [...terms].filter((value) => value.trim().length >= 2);
}

/**
 * Busqueda server-side de ventas para el modulo Pagos.
 *
 * La work queue solo contiene cuotas cobrables paginadas, por lo que NO sirve
 * como universo de busqueda: una venta con cuotas futuras, solo inicial, saldada
 * o fuera de la primera pagina seria inencontrable. Esta busqueda consulta
 * PostgreSQL directamente por cliente, cedula, telefono, solar y referencia.
 */
async function paymentsSalesSearch(req: any, res: any) {
  const startedAt = Date.now();
  const company = await resolveCompanyForRequest(req);
  const rawQuery = String(req.query.q ?? '').trim();
  const limit = Math.min(Math.max(Number(req.query.limit ?? 25), 1), 50);

  if (rawQuery.length < 2) {
    return res.json({ data: { query: rawQuery, items: [], total: 0 } });
  }

  const termList = paymentSalesSearchTerms(rawQuery);
  const digits = rawQuery.replace(/\D+/g, '');

  const containsTerms = termList.map((value) => ({
    contains: value,
    mode: 'insensitive' as const,
  }));

  const [clients, lots] = await Promise.all([
    prisma.client.findMany({
      where: {
        companyId: company.id,
        OR: containsTerms.flatMap((filter) => [
          { name: filter },
          { document: filter },
          { phone: filter },
        ]),
      },
      select: { id: true, syncId: true, name: true, document: true, phone: true },
      take: 200,
    }),
    prisma.lot.findMany({
      where: {
        companyId: company.id,
        OR: containsTerms.flatMap((filter) => [{ number: filter }, { block: filter }]),
      },
      select: { id: true, syncId: true, block: true, number: true, status: true },
      take: 200,
    }),
  ]);

  const saleConditions: any[] = [];
  if (clients.length > 0) {
    saleConditions.push({ clientId: { in: clients.map((item) => item.id) } });
    saleConditions.push({ clientSyncId: { in: clients.map((item) => item.syncId) } });
  }
  if (lots.length > 0) {
    saleConditions.push({ lotId: { in: lots.map((item) => item.id) } });
    saleConditions.push({ lotSyncId: { in: lots.map((item) => item.syncId) } });
  }
  saleConditions.push({ syncId: { contains: rawQuery, mode: 'insensitive' } });
  if (digits.length >= 6) {
    saleConditions.push({ syncId: { contains: digits, mode: 'insensitive' } });
  }

  const sales = await prisma.sale.findMany({
    where: {
      companyId: company.id,
      deletedAt: null,
      OR: saleConditions,
    },
    orderBy: { updatedAt: 'desc' },
    take: limit,
  });

  const saleIds = sales.map((sale: any) => sale.id);
  const outstandingBySaleId = new Map<string, number>();
  if (saleIds.length > 0) {
    const grouped = await prisma.installment.groupBy({
      by: ['saleId'],
      where: { companyId: company.id, deletedAt: null, saleId: { in: saleIds } },
      _sum: { totalAmount: true, paidAmount: true },
    });
    for (const row of grouped as Array<any>) {
      if (!row.saleId) continue;
      outstandingBySaleId.set(
        row.saleId,
        roundMoney(
          Math.max(toNumber(row._sum?.totalAmount) - toNumber(row._sum?.paidAmount), 0),
        ),
      );
    }
  }

  const clientSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.clientSyncId));
  const lotSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.lotSyncId));
  const sellerSyncIds = uniqueSyncIds(sales.map((sale: any) => sale.sellerSyncId));
  const [saleClients, saleLots, saleSellers] = await Promise.all([
    clientSyncIds.length
      ? prisma.client.findMany({ where: { companyId: company.id, syncId: { in: clientSyncIds } } })
      : [],
    lotSyncIds.length
      ? prisma.lot.findMany({ where: { companyId: company.id, syncId: { in: lotSyncIds } } })
      : [],
    sellerSyncIds.length
      ? prisma.seller.findMany({ where: { companyId: company.id, syncId: { in: sellerSyncIds } } })
      : [],
  ]);

  const clientsBySyncId = bySyncId(saleClients);
  const lotsBySyncId = bySyncId(saleLots);
  const sellersBySyncId = bySyncId(saleSellers);

  const items = sales.map((sale: any) =>
    serializeSaleRow(
      sale,
      clientsBySyncId,
      lotsBySyncId,
      sellersBySyncId,
      deriveSettlement(sale, outstandingBySaleId.get(sale.id) ?? 0),
    ),
  );

  return res.json({
    data: { query: rawQuery, items, total: items.length, durationMs: Date.now() - startedAt },
  });
}

export type SaleSettlement = {
  isFullyPaid: boolean;
  label: string | null;
  outstandingInstallments: number;
  tolerance: number;
};

/** Tolerancia monetaria documentada para considerar un saldo como liquidado. */
export const SETTLEMENT_TOLERANCE = 0.01;

/**
 * Clasificacion derivada de "venta definitiva".
 *
 * Se calcula desde los datos financieros autoritativos (no desde un texto de
 * estado) y exige simultaneamente: saldo liquidado, sin inicial pendiente, sin
 * obligaciones cobrables pendientes y venta no cancelada.
 */
export function deriveSettlement(sale: any, outstandingInstallments: number): SaleSettlement {
  const outstanding = roundMoney(Math.max(outstandingInstallments, 0));
  const status = String(sale?.status ?? '').trim().toLowerCase();
  const balance = roundMoney(toNumber(sale?.balance));
  const initialPending = roundMoney(toNumber(sale?.initialPendingAmount));
  const total = roundMoney(toNumber(sale?.total));
  const cancelled = Boolean(sale?.deletedAt) || status === 'cancelada';
  const isFullyPaid =
    !cancelled &&
    total > SETTLEMENT_TOLERANCE &&
    balance <= SETTLEMENT_TOLERANCE &&
    initialPending <= SETTLEMENT_TOLERANCE &&
    outstanding <= SETTLEMENT_TOLERANCE;
  return {
    isFullyPaid,
    label: isFullyPaid ? 'Saldada · Venta definitiva' : null,
    outstandingInstallments: outstanding,
    tolerance: SETTLEMENT_TOLERANCE,
  };
}

export function outstandingFromInstallments(installments: Array<any>) {
  return roundMoney(
    installments.reduce(
      (sum, item) => sum + Math.max(toNumber(item.totalAmount) - toNumber(item.paidAmount), 0),
      0,
    ),
  );
}

export function overdueInstallmentCountFromInstallments(installments: Array<any>, today: Date) {
  return installments.filter((installment) =>
    isOverdueInstallmentObligation(installment, today),
  ).length;
}

function isOpenInstallmentObligation(installment: any) {
  const closedStatuses = [
    'pagada',
    'paid',
    'ajustada',
    'adjusted',
    'cancelada',
    'cancelled',
  ];
  const status = String(installment.status ?? '').trim().toLowerCase();
  const remaining = roundMoney(
    Math.max(toNumber(installment.totalAmount) - toNumber(installment.paidAmount), 0),
  );
  return remaining > 0.009 && !closedStatuses.includes(status);
}

function isOverdueInstallmentObligation(installment: any, today: Date) {
  const dueDate = installment.dueDate instanceof Date
    ? installment.dueDate
    : new Date(installment.dueDate);
  return (
    isOpenInstallmentObligation(installment) &&
    !Number.isNaN(dueDate.getTime()) &&
    dueDate < today
  );
}

function roundMoney(value: number) {
  return Math.round(value * 100) / 100;
}

export function serializeSaleRow(
  sale: any,
  clientsBySyncId: Map<string, any>,
  lotsBySyncId: Map<string, any>,
  sellersBySyncId: Map<string, any>,
  settlement?: SaleSettlement,
  overdueInstallmentCount = 0,
) {
  const client = sale.clientSyncId ? clientsBySyncId.get(sale.clientSyncId) : null;
  const lot = sale.lotSyncId ? lotsBySyncId.get(sale.lotSyncId) : null;
  const seller = sale.sellerSyncId ? sellersBySyncId.get(sale.sellerSyncId) : null;
  return {
    ...sale,
    saleId: sale.id,
    syncId: sale.syncId,
    client: client?.name ?? null,
    clientEntity: client
      ? {
          id: client.id,
          syncId: client.syncId,
          name: client.name,
          document: client.document,
          phone: client.phone,
          address: client.address,
        }
      : null,
    cedula: client?.document ?? null,
    clientPhone: client?.phone ?? null,
    clientAddress: client?.address ?? null,
    lot: lot ? lotDisplay(lot) : null,
    lotEntity: lot
      ? {
          id: lot.id,
          syncId: lot.syncId,
          block: lot.block,
          number: lot.number,
          area: lot.area?.toString() ?? null,
          price: lot.price?.toString() ?? null,
          pricePerSquareMeter: lot.price?.toString() ?? null,
          status: lot.status,
          code: lotDisplay(lot),
        }
      : null,
    lotBlock: lot?.block ?? null,
    lotNumber: lot?.number ?? null,
    seller: seller?.name ?? null,
    sellerEntity: seller
      ? {
          id: seller.id,
          syncId: seller.syncId,
          name: seller.name,
          document: seller.document,
          phone: seller.phone,
        }
      : null,
    sellerDocument: seller?.document ?? null,
    saleDate: sale.saleDate?.toISOString() ?? null,
    total: sale.total?.toString() ?? '0',
    initialPaid: sale.initialPaid?.toString() ?? '0',
    balance: sale.balance?.toString() ?? '0',
    settlement: settlement ?? null,
    isFullyPaid: settlement?.isFullyPaid ?? false,
    settlementLabel: settlement?.label ?? null,
    overdueInstallmentCount,
    createdAt: sale.createdAt?.toISOString(),
    updatedAt: sale.updatedAt?.toISOString(),
    deletedAt: sale.deletedAt?.toISOString() ?? null,
  };
}

export function serializeInstallmentRow(installment: any) {
  return {
    id: installment.id,
    syncId: installment.syncId,
    saleId: installment.saleId,
    saleSyncId: installment.saleSyncId,
    installmentNumber: installment.installmentNumber,
    dueDate: installment.dueDate?.toISOString() ?? null,
    openingBalance: installment.openingBalance?.toString() ?? '0',
    principalAmount: installment.principalAmount?.toString() ?? '0',
    interestAmount: installment.interestAmount?.toString() ?? '0',
    amount: installment.totalAmount?.toString() ?? '0',
    totalAmount: installment.totalAmount?.toString() ?? '0',
    paidAmount: installment.paidAmount?.toString() ?? '0',
    paidPrincipalAmount: installment.paidPrincipalAmount?.toString() ?? '0',
    paidInterestAmount: installment.paidInterestAmount?.toString() ?? '0',
    endingBalance: installment.endingBalance?.toString() ?? '0',
    status: installment.status,
    createdAt: installment.createdAt?.toISOString() ?? null,
    updatedAt: installment.updatedAt?.toISOString() ?? null,
  };
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

export function installmentQueueWhere(companyId: string, state: string, today: Date) {
  const normalizedState = String(state ?? '').trim().toLowerCase();
  const closedStatuses = ['pagada', 'paid', 'ajustada', 'adjusted', 'cancelada', 'cancelled'];
  const tomorrow = new Date(today.getTime() + 24 * 60 * 60 * 1000);
  const base: any = {
    companyId,
    deletedAt: null,
  };

  switch (normalizedState) {
    case 'overdue':
      return {
        ...base,
        dueDate: { lt: today },
        totalAmount: { gt: 0 },
        NOT: { status: { in: closedStatuses } },
      };
    case 'duetoday':
    case 'due_today':
    case 'due-today':
      return {
        ...base,
        dueDate: { gte: today, lt: tomorrow },
        totalAmount: { gt: 0 },
        NOT: { status: { in: closedStatuses } },
      };
    case 'pending':
    case 'future':
      return {
        ...base,
        dueDate: { gte: tomorrow },
        totalAmount: { gt: 0 },
        NOT: { status: { in: closedStatuses } },
      };
    case 'partial':
      return {
        ...base,
        paidAmount: { gt: 0 },
        totalAmount: { gt: 0 },
        NOT: { status: { in: closedStatuses } },
      };
    case 'paid':
      return {
        ...base,
        OR: [{ status: { in: ['pagada', 'paid', 'ajustada', 'adjusted'] } }],
      };
    case 'all':
      return base;
    case 'collectible':
    default:
      return {
        ...base,
        totalAmount: { gt: 0 },
        NOT: { status: { in: closedStatuses } },
      };
  }
}

function combineSaleFilters(...filters: Array<any | null>) {
  const active = filters.filter((item) => item !== null && item !== undefined);
  if (active.length === 0) return null;
  if (active.length === 1) return active[0];
  return { AND: active };
}

async function buildPaymentSaleSearchWhere(companyId: string, search: string) {
  if (!search) {
    return null;
  }

  const contains = { contains: search, mode: 'insensitive' as const };
  const [clients, lots] = await Promise.all([
    prisma.client.findMany({
      where: {
        companyId,
        deletedAt: null,
        OR: [{ name: contains }, { document: contains }, { phone: contains }],
      },
      select: { syncId: true },
      take: 100,
    }),
    prisma.lot.findMany({
      where: {
        companyId,
        deletedAt: null,
        OR: [{ block: contains }, { number: contains }],
      },
      select: { syncId: true },
      take: 100,
    }),
  ]);

  return {
    companyId,
    deletedAt: null,
    OR: [
      { id: contains },
      { syncId: contains },
      { clientSyncId: { in: uniqueSyncIds(clients.map((client) => client.syncId)) } },
      { lotSyncId: { in: uniqueSyncIds(lots.map((lot) => lot.syncId)) } },
    ],
  };
}

function startOfUtcDay(value: Date) {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()));
}

const CANCELLED_SALE_STATUSES = [
  'cancelada',
  'cancelado',
  'anulada',
  'anulado',
  'eliminada',
  'eliminado',
];

async function clientDetail(req: any, res: any) {
  const company = await resolveCompanyForRequest(req);
  const raw = String(req.params.clientId ?? '').trim();

  const client = await prisma.client.findFirst({
    where: {
      companyId: company.id,
      deletedAt: null,
      OR: [{ id: raw }, { syncId: raw }],
    },
  });
  if (!client) {
    return res.status(404).json({
      error: { code: 'CLIENT_NOT_FOUND', message: 'Cliente no encontrado.' },
    });
  }

  const sales = await prisma.sale.findMany({
    where: {
      companyId: company.id,
      deletedAt: null,
      OR: [{ clientId: client.id }, { clientSyncId: client.syncId }],
    },
    orderBy: { saleDate: 'desc' },
  });

  const saleIds = sales.map((sale) => sale.id);
  const saleSyncIds = sales.map((sale) => sale.syncId);
  const lotIds = [
    ...new Set(sales.map((sale) => sale.lotId).filter((value): value is string => Boolean(value))),
  ];
  const sellerIds = [
    ...new Set(sales.map((sale) => sale.sellerId).filter((value): value is string => Boolean(value))),
  ];
  const sellerSyncIds = uniqueSyncIds(sales.map((sale) => sale.sellerSyncId));
  const operatorUserIds = [
    ...new Set(
      sales.map((sale) => sale.operatorUserId).filter((value): value is string => Boolean(value)),
    ),
  ];
  const operatorUserSyncIds = uniqueSyncIds(sales.map((sale) => sale.operatorUserSyncId));

  const [lots, sellers, users, installments, payments] = await Promise.all([
    prisma.lot.findMany({ where: { companyId: company.id, id: { in: lotIds } } }),
    prisma.seller.findMany({
      where: {
        companyId: company.id,
        OR: [{ id: { in: sellerIds } }, { syncId: { in: sellerSyncIds } }],
      },
    }),
    prisma.user.findMany({
      where: { OR: [{ id: { in: operatorUserIds } }, { syncId: { in: operatorUserSyncIds } }] },
      select: { id: true, syncId: true, name: true },
    }),
    prisma.installment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        OR: [{ saleId: { in: saleIds } }, { saleSyncId: { in: saleSyncIds } }],
      },
      orderBy: { installmentNumber: 'asc' },
    }),
    prisma.payment.findMany({
      where: {
        companyId: company.id,
        deletedAt: null,
        annulledAt: null,
        OR: [{ saleId: { in: saleIds } }, { saleSyncId: { in: saleSyncIds } }],
      },
      orderBy: { paidAt: 'asc' },
    }),
  ]);

  const lotsById = new Map(lots.map((lot) => [lot.id, lot]));
  const sellersById = new Map(sellers.map((seller) => [seller.id, seller]));
  const sellersBySyncId = bySyncId(sellers);
  const usersById = new Map<string, any>();
  for (const user of users) {
    usersById.set(user.id, user);
  }
  const usersBySyncId = new Map<string, any>();
  for (const user of users) {
    if (user.syncId) {
      usersBySyncId.set(user.syncId, user);
    }
  }

  const forSale = <T extends { saleId: string | null; saleSyncId: string | null }>(
    items: T[],
    sale: { id: string; syncId: string },
  ) =>
    items.filter(
      (item) => item.saleId === sale.id || (item.saleSyncId != null && item.saleSyncId === sale.syncId),
    );

  const salesJson = sales.map((sale) => {
    const lot = sale.lotId ? lotsById.get(sale.lotId) : null;
    const seller =
      (sale.sellerSyncId ? sellersBySyncId.get(sale.sellerSyncId) : undefined) ??
      (sale.sellerId ? sellersById.get(sale.sellerId) : undefined);
    const user =
      (sale.operatorUserId ? usersById.get(sale.operatorUserId) : undefined) ??
      (sale.operatorUserSyncId ? usersBySyncId.get(sale.operatorUserSyncId) : undefined);
    return {
      id: sale.id,
      syncId: sale.syncId,
      status: sale.status,
      saleDate: sale.saleDate?.toISOString() ?? null,
      createdAt: sale.createdAt?.toISOString() ?? null,
      updatedAt: sale.updatedAt?.toISOString() ?? null,
      total: sale.total?.toString() ?? '0',
      initialPercentage: sale.initialPercentage?.toString() ?? null,
      initialRequiredAmount: sale.initialRequiredAmount?.toString() ?? '0',
      initialPaid: sale.initialPaid?.toString() ?? '0',
      initialPendingAmount: sale.initialPendingAmount?.toString() ?? '0',
      reservationMinimumAmount: sale.reservationMinimumAmount?.toString() ?? null,
      reservationPaidAmount: sale.reservationPaidAmount?.toString() ?? '0',
      initialPaymentDeadline: sale.initialPaymentDeadline?.toISOString() ?? null,
      activationDate: sale.activationDate?.toISOString() ?? null,
      financedBalance: sale.financedBalance?.toString() ?? '0',
      monthlyInterestRate: sale.monthlyInterestRate?.toString() ?? null,
      installmentCount: sale.installmentCount,
      balance: sale.balance?.toString() ?? '0',
      lotCode: lot ? lotDisplay(lot) : null,
      lot: lot
        ? {
            id: lot.id,
            syncId: lot.syncId,
            block: lot.block,
            number: lot.number,
            area: lot.area?.toString() ?? null,
            price: lot.price?.toString() ?? null,
            status: lot.status,
          }
        : null,
      sellerName: seller?.name ?? null,
      operatorUserName: user?.name ?? null,
      installments: forSale(installments, sale).map(serializeInstallmentRow),
      payments: forSale(payments, sale).map(serializePaymentRow),
    };
  });

  const isCancelled = (sale: any) =>
    CANCELLED_SALE_STATUSES.includes(String(sale.status ?? '').toLowerCase());
  const activeSales = sales.filter((sale) => !isCancelled(sale));
  const summary = {
    sales: sales.length,
    activeSales: activeSales.length,
    installments: installments.length,
    payments: payments.length,
    totalSold: sales.reduce((acc, sale) => acc + toNumber(sale.total), 0),
    totalPaid: payments.reduce((acc, payment) => acc + toNumber(payment.amount), 0),
    pendingBalance: activeSales.reduce((acc, sale) => acc + toNumber(sale.balance), 0),
  };

  return res.json({
    data: {
      client: {
        id: client.id,
        syncId: client.syncId,
        name: client.name,
        document: client.document,
        phone: client.phone,
        address: client.address,
        createdAt: client.createdAt?.toISOString() ?? null,
        updatedAt: client.updatedAt?.toISOString() ?? null,
      },
      summary,
      sales: salesJson,
    },
  });
}

function serializePaymentRow(payment: any) {
  return {
    id: payment.id,
    syncId: payment.syncId,
    saleId: payment.saleId,
    saleSyncId: payment.saleSyncId,
    installmentId: payment.installmentId,
    installmentSyncId: payment.installmentSyncId,
    paidAt: payment.paidAt?.toISOString() ?? null,
    amount: payment.amount?.toString() ?? '0',
    method: payment.method,
    paymentType: payment.paymentType,
    reference: payment.reference,
    yearToPay: payment.yearToPay,
    annulledAt: payment.annulledAt?.toISOString() ?? null,
    annulmentReason: payment.annulmentReason ?? null,
    annulledByUserId: payment.annulledByUserId ?? null,
    annulledByName: payment.annulledByUser?.name ?? null,
    performedByUserId: payment.raw?.annulmentAudit?.performedByUserId ?? null,
    authorizedByUserId: payment.raw?.annulmentAudit?.authorizedByUserId ?? null,
    authorizedByAdmin: payment.raw?.annulmentAudit?.override === true,
  };
}

function toNumber(value: any) {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}
