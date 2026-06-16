import { Prisma } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';

const rowSchema = z.record(z.unknown()).and(
  z
    .object({
      sync_id: z.string().optional(),
      syncId: z.string().optional(),
      version: z.coerce.number().int().optional(),
      deleted_at: z.string().nullable().optional(),
      deletedAt: z.string().nullable().optional(),
    })
    .passthrough(),
);

const uploadSchema = z.object({
  device_id: z.string().optional(),
  deviceId: z.string().optional(),
  records: z.record(z.array(rowSchema).optional()),
});

type Row = Record<string, unknown>;

export const syncRouter = Router();

syncRouter.post('/upload', async (req, res) => {
  const parsed = uploadSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      message: 'Payload de sync invalido.',
      error: { message: 'Payload de sync invalido.' },
    });
  }

  const records = parsed.data.records;
  const deviceId = stringValue(parsed.data.device_id, parsed.data.deviceId) ?? 'unknown-device';
  const company = await resolveCompanyForRequest(req);

  const uploaded = {
    clients: records.clients ?? [],
    sellers: records.sellers ?? [],
    products: [...(records.products ?? []), ...(records.lots ?? []), ...(records.solares ?? [])],
    sales: records.sales ?? [],
    installments: [...(records.installments ?? []), ...(records.cuotas ?? [])],
    payments: records.payments ?? [],
  };

  const ack = {
    clients: await upsertClients(company.id, uploaded.clients),
    sellers: await upsertSellers(company.id, uploaded.sellers),
    products: await upsertLots(company.id, uploaded.products),
    sales: await upsertSales(company.id, uploaded.sales),
    installments: await upsertInstallments(company.id, uploaded.installments),
    payments: await upsertPayments(company.id, uploaded.payments),
  };

  const receivedCounts = {
    clients: uploaded.clients.length,
    sellers: uploaded.sellers.length,
    products: uploaded.products.length,
    sales: uploaded.sales.length,
    installments: uploaded.installments.length,
    payments: uploaded.payments.length,
  };
  const appliedCounts = Object.fromEntries(
    Object.entries(ack).map(([scope, rows]) => [scope, rows.length]),
  );

  await prisma.syncBatch.create({
    data: {
      companyId: company.id,
      deviceId,
      receivedCounts,
      appliedCounts,
    },
  });

  return res.json({
    company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
    records: ack,
    server_time: new Date().toISOString(),
    applied: appliedCounts,
  });
});

syncRouter.get('/download', handleDownload);
syncRouter.get('/changes', handleDownload);

async function handleDownload(req: any, res: any) {
  const company = await resolveCompanyForRequest(req);
  const scopeCursors = parseScopeCursors(req.query.scope_cursors);
  const updatedSince = dateValue(req.query.updatedSince);
  const records = {
    clients: await listClients(company.id, scopeCursors.clients ?? updatedSince),
    sellers: await listSellers(company.id, scopeCursors.sellers ?? updatedSince),
    products: await listLots(company.id, scopeCursors.products ?? scopeCursors.lots ?? updatedSince),
    sales: await listSales(company.id, scopeCursors.sales ?? updatedSince),
    installments: await listInstallments(company.id, scopeCursors.installments ?? scopeCursors.cuotas ?? updatedSince),
    payments: await listPayments(company.id, scopeCursors.payments ?? updatedSince),
  };
  const serverTime = new Date().toISOString();

  return res.json({
    company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
    records,
    server_time: serverTime,
    scope_cursors: {
      clients: latestCursor(records.clients, serverTime),
      sellers: latestCursor(records.sellers, serverTime),
      products: latestCursor(records.products, serverTime),
      sales: latestCursor(records.sales, serverTime),
      installments: latestCursor(records.installments, serverTime),
      payments: latestCursor(records.payments, serverTime),
    },
  });
}

syncRouter.get('/status', async (req, res) => {
  const company = await resolveCompanyForRequest(req);
  const where = { companyId: company.id, deletedAt: null };
  const lastBatch = await prisma.syncBatch.findFirst({
    where: { companyId: company.id },
    orderBy: { createdAt: 'desc' },
  });
  const [clients, sellers, products, sales, installments, payments] = await Promise.all([
    prisma.client.count({ where }),
    prisma.seller.count({ where }),
    prisma.lot.count({ where }),
    prisma.sale.count({ where }),
    prisma.installment.count({ where }),
    prisma.payment.count({ where }),
  ]);
  return res.json({
    ok: true,
    company: { id: company.id, tenantKey: company.tenantKey, name: company.name },
    lastBatch,
    counts: { clients, sellers, products, sales, installments, payments },
    server_time: new Date().toISOString(),
  });
});

function syncId(row: Row) {
  return String(row.sync_id ?? row.syncId ?? '').trim();
}

function versionValue(row: Row) {
  const value = Number(row.version ?? 1);
  return Number.isFinite(value) && value > 0 ? Math.trunc(value) : 1;
}

function deletedAt(row: Row) {
  return dateValue(row.deleted_at ?? row.deletedAt);
}

function dateValue(value: unknown) {
  if (value == null || String(value).trim() === '') return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function intValue(value: unknown) {
  if (value == null || String(value).trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

function stringValue(...values: unknown[]) {
  for (const value of values) {
    const text = String(value ?? '').trim();
    if (text) return text;
  }
  return null;
}

function decimalValue(...values: unknown[]) {
  const value = stringValue(...values);
  if (!value) return new Prisma.Decimal(0);
  const normalized = value.replace(/,/g, '');
  return new Prisma.Decimal(Number.isFinite(Number(normalized)) ? normalized : 0);
}

function rawJson(row: Row): Prisma.InputJsonObject {
  return row as Prisma.InputJsonObject;
}

function whereUpdatedSince(companyId: string, updatedSince?: Date | null) {
  return updatedSince ? { companyId, updatedAt: { gt: updatedSince } } : { companyId };
}

function parseScopeCursors(value: unknown): Record<string, Date | null> {
  if (value == null || String(value).trim() === '') return {};
  try {
    const decoded = JSON.parse(String(value));
    if (!decoded || typeof decoded !== 'object') return {};
    return Object.fromEntries(
      Object.entries(decoded as Record<string, unknown>).map(([scope, date]) => [scope, dateValue(date)]),
    );
  } catch {
    return {};
  }
}

function latestCursor(rows: Row[], fallback: string) {
  let latest = dateValue(fallback) ?? new Date();
  for (const row of rows) {
    const value = dateValue(row.updated_at ?? row.updatedAt);
    if (value && value > latest) latest = value;
  }
  return latest.toISOString();
}

async function upsertClients(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      name: stringValue(row.nombre, row.name, row.full_name) ?? 'Sin nombre',
      document: stringValue(row.cedula, row.document_id, row.document),
      phone: stringValue(row.telefono, row.phone),
      address: stringValue(row.direccion, row.address),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.client.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(clientRecord(saved));
  }
  return ack;
}

async function upsertSellers(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      name: stringValue(row.nombre, row.name, row.full_name) ?? 'Sin nombre',
      document: stringValue(row.cedula, row.document_id, row.document),
      phone: stringValue(row.telefono, row.phone),
      active: String(row.activo ?? row.active ?? 'true') !== 'false',
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.seller.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(sellerRecord(saved));
  }
  return ack;
}

async function upsertLots(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      block: stringValue(row.block_number, row.manzana_numero, row.block, row.manzana),
      number: stringValue(row.lot_number, row.solar_numero, row.number, row.numero),
      status: stringValue(row.status, row.estado),
      area: decimalValue(row.area, row.metros_cuadrados),
      price: decimalValue(row.price_per_square_meter, row.precio_por_metro, row.price),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.lot.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(lotRecord(saved));
  }
  return ack;
}

async function upsertSales(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      lotSyncId: stringValue(row.product_sync_id, row.lot_sync_id, row.solar_sync_id),
      sellerSyncId: stringValue(row.seller_sync_id, row.vendedor_sync_id),
      saleDate: dateValue(row.sale_date ?? row.fecha_venta),
      status: stringValue(row.status, row.estado),
      total: decimalValue(row.sale_price, row.precio_venta, row.total),
      initialPaid: decimalValue(row.paid_initial_payment, row.inicial, row.initialPaid),
      balance: decimalValue(row.saldo_pendiente, row.balance),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.sale.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(saleRecord(saved));
  }
  return ack;
}

async function upsertInstallments(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      saleSyncId: stringValue(row.sale_sync_id, row.venta_sync_id),
      installmentNumber: intValue(row.installment_number ?? row.numero_cuota),
      dueDate: dateValue(row.due_date ?? row.fecha_vencimiento),
      openingBalance: decimalValue(row.opening_balance, row.saldo_inicial),
      principalAmount: decimalValue(row.principal_amount, row.capital_cuota),
      interestAmount: decimalValue(row.interest_amount, row.interes_cuota),
      totalAmount: decimalValue(row.total_amount, row.monto_cuota),
      paidAmount: decimalValue(row.paid_amount, row.monto_pagado),
      paidPrincipalAmount: decimalValue(row.paid_principal_amount, row.capital_pagado),
      paidInterestAmount: decimalValue(row.paid_interest_amount, row.interes_pagado),
      endingBalance: decimalValue(row.ending_balance, row.saldo_final),
      status: stringValue(row.status, row.estado),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.installment.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(installmentRecord(saved));
  }
  return ack;
}

async function upsertPayments(companyId: string, rows: Row[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      saleSyncId: stringValue(row.sale_sync_id, row.venta_sync_id),
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      installmentSyncId: stringValue(row.installment_sync_id, row.cuota_sync_id),
      paidAt: dateValue(row.payment_date ?? row.fecha_pago ?? row.paidAt),
      amount: decimalValue(row.amount_paid, row.monto_pagado, row.amount),
      method: stringValue(row.payment_method, row.metodo_pago, row.method),
      paymentType: stringValue(row.payment_type, row.tipo_pago),
      reference: stringValue(row.reference, row.referencia),
      yearToPay: intValue(row.year_to_pay ?? row.ano_a_pagar),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const saved = await prisma.payment.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(paymentRecord(saved));
  }
  return ack;
}

async function listClients(companyId: string, updatedSince?: Date | null) {
  return (await prisma.client.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(clientRecord);
}

async function listSellers(companyId: string, updatedSince?: Date | null) {
  return (await prisma.seller.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(sellerRecord);
}

async function listLots(companyId: string, updatedSince?: Date | null) {
  return (await prisma.lot.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(lotRecord);
}

async function listSales(companyId: string, updatedSince?: Date | null) {
  return (await prisma.sale.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(saleRecord);
}

async function listInstallments(companyId: string, updatedSince?: Date | null) {
  return (await prisma.installment.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(installmentRecord);
}

async function listPayments(companyId: string, updatedSince?: Date | null) {
  return (await prisma.payment.findMany({ where: whereUpdatedSince(companyId, updatedSince), orderBy: { updatedAt: 'asc' } })).map(paymentRecord);
}

function clientRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    name: row.name,
    document_id: row.document,
    cedula: row.document,
    phone: row.phone,
    address: row.address,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}

function sellerRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    name: row.name,
    document_id: row.document,
    cedula: row.document,
    phone: row.phone,
    active: row.active,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}

function lotRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    block_number: row.block,
    lot_number: row.number,
    area: row.area?.toString() ?? '0',
    price_per_square_meter: row.price?.toString() ?? '0',
    status: row.status,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}

function saleRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    client_sync_id: row.clientSyncId,
    product_sync_id: row.lotSyncId,
    seller_sync_id: row.sellerSyncId,
    sale_date: row.saleDate?.toISOString() ?? null,
    status: row.status,
    sale_price: row.total?.toString() ?? '0',
    paid_initial_payment: row.initialPaid?.toString() ?? '0',
    saldo_pendiente: row.balance?.toString() ?? '0',
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}

function installmentRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    sale_sync_id: row.saleSyncId,
    installment_number: row.installmentNumber,
    due_date: row.dueDate?.toISOString() ?? null,
    opening_balance: row.openingBalance?.toString() ?? '0',
    principal_amount: row.principalAmount?.toString() ?? '0',
    interest_amount: row.interestAmount?.toString() ?? '0',
    total_amount: row.totalAmount?.toString() ?? '0',
    paid_amount: row.paidAmount?.toString() ?? '0',
    paid_principal_amount: row.paidPrincipalAmount?.toString() ?? '0',
    paid_interest_amount: row.paidInterestAmount?.toString() ?? '0',
    ending_balance: row.endingBalance?.toString() ?? '0',
    status: row.status,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}

function paymentRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    sale_sync_id: row.saleSyncId,
    client_sync_id: row.clientSyncId,
    installment_sync_id: row.installmentSyncId,
    payment_date: row.paidAt?.toISOString() ?? null,
    amount_paid: row.amount?.toString() ?? '0',
    payment_method: row.method,
    payment_type: row.paymentType,
    reference: row.reference,
    year_to_pay: row.yearToPay,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}
