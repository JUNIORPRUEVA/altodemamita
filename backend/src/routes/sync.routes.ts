import { Router } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { syncGuard } from '../auth';
import { prisma } from '../prisma';

const rowSchema = z.record(z.unknown()).and(
  z.object({
    sync_id: z.string().optional(),
    syncId: z.string().optional(),
    version: z.coerce.number().int().optional(),
    deleted_at: z.string().nullable().optional(),
    deletedAt: z.string().nullable().optional(),
  }).passthrough(),
);

const uploadSchema = z.object({
  deviceId: z.string().min(1),
  records: z.object({
    clients: z.array(rowSchema).optional(),
    sellers: z.array(rowSchema).optional(),
    lots: z.array(rowSchema).optional(),
    solares: z.array(rowSchema).optional(),
    sales: z.array(rowSchema).optional(),
    payments: z.array(rowSchema).optional(),
  }),
});

export const syncRouter = Router();

syncRouter.post('/upload', syncGuard, async (req, res) => {
  const parsed = uploadSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: { message: 'Payload de sync invalido.' } });
  }

  const { deviceId, records } = parsed.data;
  const counts = {
    clients: await upsertClients(records.clients ?? []),
    sellers: await upsertSellers(records.sellers ?? []),
    lots: await upsertLots([...(records.lots ?? []), ...(records.solares ?? [])]),
    sales: await upsertSales(records.sales ?? []),
    payments: await upsertPayments(records.payments ?? []),
  };

  await prisma.syncBatch.create({
    data: {
      deviceId,
      receivedCounts: {
        clients: records.clients?.length ?? 0,
        sellers: records.sellers?.length ?? 0,
        lots: (records.lots?.length ?? 0) + (records.solares?.length ?? 0),
        sales: records.sales?.length ?? 0,
        payments: records.payments?.length ?? 0,
      },
      appliedCounts: counts,
    },
  });

  return res.json({ data: { applied: counts, serverTime: new Date().toISOString() } });
});

syncRouter.get('/status', syncGuard, async (_req, res) => {
  const lastBatch = await prisma.syncBatch.findFirst({ orderBy: { createdAt: 'desc' } });
  return res.json({ data: { lastBatch } });
});

function syncId(row: Record<string, unknown>) {
  return String(row.sync_id ?? row.syncId ?? '').trim();
}

function deletedAt(row: Record<string, unknown>) {
  const value = row.deleted_at ?? row.deletedAt;
  if (value == null || String(value).trim() === '') return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function dateValue(value: unknown) {
  if (value == null || String(value).trim() === '') return null;
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function stringValue(...values: unknown[]) {
  for (const value of values) {
    const text = String(value ?? '').trim();
    if (text) return text;
  }
  return null;
}

function decimalValue(value: unknown) {
  const text = String(value ?? '').trim();
  if (!text) return new Prisma.Decimal(0);
  const normalized = text.replace(',', '.');
  return new Prisma.Decimal(Number.isFinite(Number(normalized)) ? normalized : 0);
}

function rawJson(row: Record<string, unknown>): Prisma.InputJsonObject {
  return row as Prisma.InputJsonObject;
}

async function upsertClients(rows: Record<string, unknown>[]) {
  let count = 0;
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    await prisma.client.upsert({
      where: { syncId: id },
      create: {
        syncId: id,
        name: stringValue(row.nombre, row.name) ?? 'Sin nombre',
        document: stringValue(row.cedula, row.documento, row.document),
        phone: stringValue(row.telefono, row.phone),
        address: stringValue(row.direccion, row.address),
        raw: rawJson(row),
        version: Number(row.version ?? 1),
        deletedAt: deletedAt(row),
      },
      update: {
        name: stringValue(row.nombre, row.name) ?? 'Sin nombre',
        document: stringValue(row.cedula, row.documento, row.document),
        phone: stringValue(row.telefono, row.phone),
        address: stringValue(row.direccion, row.address),
        raw: rawJson(row),
        version: Number(row.version ?? 1),
        deletedAt: deletedAt(row),
      },
    });
    count += 1;
  }
  return count;
}

async function upsertSellers(rows: Record<string, unknown>[]) {
  let count = 0;
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      name: stringValue(row.nombre, row.name) ?? 'Sin nombre',
      phone: stringValue(row.telefono, row.phone),
      active: String(row.activo ?? row.active ?? 'true') !== 'false',
      raw: rawJson(row),
      version: Number(row.version ?? 1),
      deletedAt: deletedAt(row),
    };
    await prisma.seller.upsert({ where: { syncId: id }, create: { syncId: id, ...data }, update: data });
    count += 1;
  }
  return count;
}

async function upsertLots(rows: Record<string, unknown>[]) {
  let count = 0;
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      block: stringValue(row.manzana_numero, row.block, row.manzana),
      number: stringValue(row.solar_numero, row.number, row.numero),
      status: stringValue(row.estado, row.status),
      area: decimalValue(row.metros_cuadrados ?? row.area),
      price: decimalValue(row.precio_por_metro ?? row.price),
      raw: rawJson(row),
      version: Number(row.version ?? 1),
      deletedAt: deletedAt(row),
    };
    await prisma.lot.upsert({ where: { syncId: id }, create: { syncId: id, ...data }, update: data });
    count += 1;
  }
  return count;
}

async function upsertSales(rows: Record<string, unknown>[]) {
  let count = 0;
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      lotSyncId: stringValue(row.lot_sync_id, row.solar_sync_id, row.product_sync_id),
      sellerSyncId: stringValue(row.seller_sync_id, row.vendedor_sync_id),
      saleDate: dateValue(row.fecha_venta ?? row.saleDate),
      status: stringValue(row.estado, row.status),
      total: decimalValue(row.precio_total ?? row.total),
      initialPaid: decimalValue(row.inicial ?? row.initialPaid),
      balance: decimalValue(row.saldo_pendiente ?? row.balance),
      raw: rawJson(row),
      version: Number(row.version ?? 1),
      deletedAt: deletedAt(row),
    };
    await prisma.sale.upsert({ where: { syncId: id }, create: { syncId: id, ...data }, update: data });
    count += 1;
  }
  return count;
}

async function upsertPayments(rows: Record<string, unknown>[]) {
  let count = 0;
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      saleSyncId: stringValue(row.sale_sync_id, row.venta_sync_id),
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      paidAt: dateValue(row.fecha_pago ?? row.paidAt),
      amount: decimalValue(row.monto ?? row.amount),
      method: stringValue(row.metodo_pago, row.method),
      raw: rawJson(row),
      version: Number(row.version ?? 1),
      deletedAt: deletedAt(row),
    };
    await prisma.payment.upsert({ where: { syncId: id }, create: { syncId: id, ...data }, update: data });
    count += 1;
  }
  return count;
}
