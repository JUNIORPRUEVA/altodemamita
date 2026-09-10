import { Router } from "express";
import { authGuard } from "../auth";
import { resolveCompanyForRequest } from "../companyIdentity";
import { prisma } from "../prisma";
import { serializeInstallmentRow, serializeSaleRow } from "./owner.routes";

export const customerRouter = Router();

customerRouter.use(authGuard);

customerRouter.get("/me", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  return res.json({ data: customerProfile(context) });
});

customerRouter.get("/snapshot", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  const snapshot = await buildCustomerSnapshot(context);
  return res.json({ data: snapshot });
});

customerRouter.get("/project", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  const snapshot = await buildCustomerSnapshot(context);
  return res.json({ data: snapshot.project });
});

customerRouter.get("/sale", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  const snapshot = await buildCustomerSnapshot(context);
  return res.json({ data: snapshot.sales[0] ?? null });
});

customerRouter.get("/installments", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  const snapshot = await buildCustomerSnapshot(context);
  return res.json({ data: { items: snapshot.installments } });
});

customerRouter.get("/payments", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);
  const snapshot = await buildCustomerSnapshot(context);
  return res.json({ data: { items: snapshot.payments } });
});

customerRouter.get("/lots/:lotId", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);

  const lotId = String(req.params.lotId ?? "").trim();
  const sale = await prisma.sale.findFirst({
    where: {
      companyId: context.company.id,
      deletedAt: null,
      lotId,
      OR: customerSaleWhere(context.client),
    },
    select: { lotId: true },
  });
  if (!sale?.lotId) {
    return res.status(404).json({
      error: { code: "LOT_NOT_FOUND", message: "Solar no encontrado." },
    });
  }
  const lot = await prisma.lot.findFirst({
    where: { id: sale.lotId, companyId: context.company.id, deletedAt: null },
  });
  if (!lot) {
    return res.status(404).json({
      error: { code: "LOT_NOT_FOUND", message: "Solar no encontrado." },
    });
  }
  return res.json({ data: serializeCustomerLot(lot) });
});

customerRouter.get("/sales/:saleId", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);

  const saleId = String(req.params.saleId ?? "").trim();
  const sale = await prisma.sale.findFirst({
    where: {
      companyId: context.company.id,
      deletedAt: null,
      id: saleId,
      OR: customerSaleWhere(context.client),
    },
  });
  if (!sale) {
    return res.status(404).json({
      error: { code: "SALE_NOT_FOUND", message: "Venta no encontrada." },
    });
  }
  const snapshot = await buildCustomerSnapshot(context);
  const detail = snapshot.sales.find((item) => item.id === sale.id) ?? null;
  return res.json({ data: detail });
});

customerRouter.get("/installments/:installmentId", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);

  const installmentId = String(req.params.installmentId ?? "").trim();
  const installment = await prisma.installment.findFirst({
    where: {
      id: installmentId,
      companyId: context.company.id,
      deletedAt: null,
      sale: { OR: customerSaleWhere(context.client) },
    },
  });
  if (!installment) {
    return res.status(404).json({
      error: { code: "INSTALLMENT_NOT_FOUND", message: "Cuota no encontrada." },
    });
  }
  return res.json({ data: serializeInstallmentRow(installment) });
});

customerRouter.get("/payments/:paymentId", async (req, res) => {
  const context = await resolveCustomerContext(req);
  if ("error" in context) return sendCustomerError(res, context.error);

  const paymentId = String(req.params.paymentId ?? "").trim();
  const payment = await prisma.payment.findFirst({
    where: {
      id: paymentId,
      companyId: context.company.id,
      deletedAt: null,
      annulledAt: null,
      OR: [
        { clientId: context.client.id },
        { clientSyncId: context.client.syncId },
        { sale: { OR: customerSaleWhere(context.client) } },
      ],
    },
  });
  if (!payment) {
    return res.status(404).json({
      error: { code: "PAYMENT_NOT_FOUND", message: "Pago no encontrado." },
    });
  }
  return res.json({ data: serializeCustomerPayment(payment) });
});

type CustomerContext = {
  company: { id: string; tenantKey: string; name: string };
  user: {
    id: string;
    email: string;
    name: string;
    raw: unknown;
    remoteAuthId: string | null;
    authSource: string | null;
  };
  client: {
    id: string;
    syncId: string;
    name: string;
    document: string | null;
    phone: string | null;
    address: string | null;
  };
};

type CustomerError =
  "CUSTOMER_LINK_REQUIRED" | "CUSTOMER_NOT_FOUND" | "USER_NOT_FOUND";

export function extractCustomerClientSyncId(user: {
  raw?: unknown;
  remoteAuthId?: string | null;
  authSource?: string | null;
}) {
  const raw = isRecord(user.raw) ? user.raw : {};
  const direct =
    textValue(raw.customerClientSyncId) ??
    textValue(raw.clientSyncId) ??
    textValue(raw.client_sync_id) ??
    textValue(raw.customer_client_sync_id);
  if (direct) return direct;

  const customer = isRecord(raw.customer) ? raw.customer : null;
  const nested =
    textValue(customer?.clientSyncId) ??
    textValue(customer?.client_sync_id) ??
    textValue(customer?.syncId) ??
    textValue(customer?.sync_id);
  if (nested) return nested;

  const authSource = user.authSource?.trim().toLowerCase() ?? "";
  if (["customer", "client", "app_owner_customer"].includes(authSource)) {
    return textValue(user.remoteAuthId);
  }
  return null;
}

async function resolveCustomerContext(
  req: any,
): Promise<CustomerContext | { error: CustomerError }> {
  const company = await resolveCompanyForRequest(req);
  const authUser = req.user;
  if (!authUser) return { error: "USER_NOT_FOUND" };

  const user = await prisma.user.findFirst({
    where: { id: authUser.id, active: true, deletedAt: null },
    select: {
      id: true,
      email: true,
      name: true,
      companyId: true,
      raw: true,
      remoteAuthId: true,
      authSource: true,
    },
  });
  if (!user || (user.companyId && user.companyId !== company.id)) {
    return { error: "USER_NOT_FOUND" };
  }

  const clientSyncId = extractCustomerClientSyncId(user);
  if (!clientSyncId) return { error: "CUSTOMER_LINK_REQUIRED" };

  const client = await prisma.client.findFirst({
    where: {
      companyId: company.id,
      syncId: clientSyncId,
      deletedAt: null,
    },
    select: {
      id: true,
      syncId: true,
      name: true,
      document: true,
      phone: true,
      address: true,
    },
  });
  if (!client) return { error: "CUSTOMER_NOT_FOUND" };

  return { company, user, client };
}

async function buildCustomerSnapshot(context: CustomerContext) {
  const sales = await prisma.sale.findMany({
    where: {
      companyId: context.company.id,
      deletedAt: null,
      OR: customerSaleWhere(context.client),
    },
    orderBy: [{ saleDate: "desc" }, { updatedAt: "desc" }],
  });

  const saleIds = sales.map((sale) => sale.id);
  const saleSyncIds = sales.map((sale) => sale.syncId);
  const lotSyncIds = unique(sales.map((sale) => sale.lotSyncId));
  const sellerSyncIds = unique(sales.map((sale) => sale.sellerSyncId));

  const [lots, sellers, installments, payments] = await Promise.all([
    lotSyncIds.length === 0
      ? Promise.resolve([])
      : prisma.lot.findMany({
          where: {
            companyId: context.company.id,
            syncId: { in: lotSyncIds },
            deletedAt: null,
          },
        }),
    sellerSyncIds.length === 0
      ? Promise.resolve([])
      : prisma.seller.findMany({
          where: {
            companyId: context.company.id,
            syncId: { in: sellerSyncIds },
            deletedAt: null,
          },
        }),
    saleIds.length === 0 && saleSyncIds.length === 0
      ? Promise.resolve([])
      : prisma.installment.findMany({
          where: {
            companyId: context.company.id,
            deletedAt: null,
            OR: [
              { saleId: { in: saleIds } },
              { saleSyncId: { in: saleSyncIds } },
            ],
          },
          orderBy: [{ dueDate: "asc" }, { installmentNumber: "asc" }],
        }),
    saleIds.length === 0 && saleSyncIds.length === 0
      ? Promise.resolve([])
      : prisma.payment.findMany({
          where: {
            companyId: context.company.id,
            deletedAt: null,
            annulledAt: null,
            OR: [
              { clientId: context.client.id },
              { clientSyncId: context.client.syncId },
              { saleId: { in: saleIds } },
              { saleSyncId: { in: saleSyncIds } },
            ],
          },
          orderBy: [{ paidAt: "desc" }, { updatedAt: "desc" }],
        }),
  ]);

  const clientMap = new Map([[context.client.syncId, context.client]]);
  const lotMap = bySyncId(lots);
  const sellerMap = bySyncId(sellers);
  const serializedSales = sales.map((sale) =>
    serializeSaleRow(sale, clientMap, lotMap, sellerMap),
  );
  const serializedInstallments = installments.map(serializeInstallmentRow);
  const serializedPayments = payments.map((payment) =>
    serializeCustomerPayment(payment),
  );

  return {
    customer: customerProfile(context),
    project: {
      client: customerProfile(context).client,
      sales: serializedSales,
      lots: lots.map(serializeCustomerLot),
    },
    dashboard: {
      company: context.company,
      counts: {
        clients: 1,
        sellers: sellers.length,
        lots: lots.length,
        sales: sales.length,
        installments: installments.length,
        payments: payments.length,
      },
      totals: customerTotals(sales, installments, payments),
      serverTime: new Date().toISOString(),
      scope: "authenticated-customer",
    },
    clients: [customerProfile(context).client],
    sellers,
    lots: lots.map(serializeCustomerLot),
    sales: serializedSales,
    installments: serializedInstallments,
    payments: serializedPayments,
  };
}

function serializeCustomerLot(lot: {
  id: string;
  syncId: string;
  block: string | null;
  number: string | null;
  status: string | null;
  area: { toString(): string } | null;
  price: { toString(): string } | null;
  updatedAt?: Date | null;
}) {
  return {
    id: lot.id,
    syncId: lot.syncId,
    block: lot.block,
    number: lot.number,
    display: lotDisplay(lot),
    status: lot.status,
    area: lot.area?.toString() ?? null,
    price: lot.price?.toString() ?? null,
    updatedAt: lot.updatedAt?.toISOString() ?? null,
  };
}

function customerProfile(context: CustomerContext) {
  return {
    user: {
      id: context.user.id,
      email: context.user.email,
      name: context.user.name,
    },
    client: {
      id: context.client.id,
      syncId: context.client.syncId,
      name: context.client.name,
      document: context.client.document,
      phone: context.client.phone,
      address: context.client.address,
    },
  };
}

function customerSaleWhere(client: CustomerContext["client"]) {
  return [{ clientId: client.id }, { clientSyncId: client.syncId }];
}

function customerTotals(sales: any[], installments: any[], payments: any[]) {
  const sold = sales.reduce((sum, sale) => sum + Number(sale.total ?? 0), 0);
  const balance = sales.reduce(
    (sum, sale) => sum + Number(sale.balance ?? 0),
    0,
  );
  const paid = payments.reduce(
    (sum, payment) => sum + Number(payment.amount ?? 0),
    0,
  );
  const overdue = installments.filter((installment) => {
    const status = String(installment.status ?? "").toLowerCase();
    if (status.includes("venc") || status.includes("overdue")) return true;
    if (status.includes("pag") || status.includes("paid")) return false;
    return installment.dueDate ? installment.dueDate < startOfToday() : false;
  }).length;
  return {
    sold: sold.toFixed(2),
    balance: balance.toFixed(2),
    paid: paid.toFixed(2),
    overdueInstallments: overdue,
  };
}

function serializeCustomerPayment(payment: any) {
  return {
    id: payment.id,
    syncId: payment.syncId,
    saleId: payment.saleId,
    saleSyncId: payment.saleSyncId,
    clientId: payment.clientId,
    clientSyncId: payment.clientSyncId,
    installmentId: payment.installmentId,
    installmentSyncId: payment.installmentSyncId,
    paidAt: payment.paidAt?.toISOString() ?? null,
    amount: payment.amount?.toString() ?? "0",
    method: payment.method,
    paymentType: payment.paymentType,
    reference: payment.reference,
    yearToPay: payment.yearToPay,
    principalApplied: payment.principalApplied?.toString() ?? "0",
    interestApplied: payment.interestApplied?.toString() ?? "0",
    updatedAt: payment.updatedAt?.toISOString() ?? null,
  };
}

function sendCustomerError(res: any, error: CustomerError) {
  const status = error === "USER_NOT_FOUND" ? 401 : 403;
  const messages: Record<CustomerError, string> = {
    USER_NOT_FOUND: "No autenticado.",
    CUSTOMER_LINK_REQUIRED: "Usuario no vinculado a un cliente.",
    CUSTOMER_NOT_FOUND: "Cliente no encontrado.",
  };
  return res
    .status(status)
    .json({ error: { code: error, message: messages[error] } });
}

function textValue(value: unknown) {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unique(values: Array<string | null>) {
  return [
    ...new Set(
      values.filter((value): value is string => Boolean(value?.trim())),
    ),
  ];
}

function bySyncId<T extends { syncId: string }>(items: T[]) {
  return new Map(items.map((item) => [item.syncId, item]));
}

function lotDisplay(lot: { block: string | null; number: string | null }) {
  const block = lot.block?.trim() ?? "";
  const number = lot.number?.trim() ?? "";
  if (block && number) return `M${block}-S${number}`;
  if (number) return `Solar ${number}`;
  if (block) return `Manzana ${block}`;
  return null;
}

function startOfToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}
