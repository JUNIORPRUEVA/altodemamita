import { Router } from 'express';
import { z } from 'zod';
import { authenticateRequest } from '../auth';
import { config } from '../config';
import { resolveCompanyForRequest } from '../companyIdentity';
import { prisma } from '../prisma';
import {
  canonicalInstallmentDueDate,
  isCanonicalInstallmentDueDate,
} from '../services/financing.service';
import {
  isTimeDerivedOverdueStatus,
  resolvePersistedInstallmentStatus,
} from '../services/installmentStatus.service';
import { authoritativeErrorResponse } from '../services/authoritativeErrors.service';
import { AuthoritativePaymentService } from '../services/authoritativePayment.service';

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
const authoritativePayments = new AuthoritativePaymentService(prisma);

syncRouter.post('/upload', async (req, res) => {
  const authUser = await authenticateRequest(req);
  if (!authUser && !config.legacySyncAllowAnonymous) {
    console.warn('[LegacySync] anonymous upload rejected');
    return res.status(401).json({
      error: {
        code: 'LEGACY_SYNC_AUTH_REQUIRED',
        message: 'Sync requiere autenticacion durante la transicion autoritativa.',
      },
    });
  }
  if (!authUser) {
    console.warn('[LegacySync] anonymous upload accepted by transition flag');
  }
  const parsed = uploadSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      message: 'Payload de sync invalido.',
      error: { message: 'Payload de sync invalido.' },
    });
  }

  const records = parsed.data.records;
  if (config.authoritativeMode && hasFinancialSyncRecords(records)) {
    return res.status(409).json({
      error: {
        code: 'LEGACY_FINANCIAL_SYNC_FROZEN',
        message:
          'Las ventas, cuotas y pagos deben escribirse por endpoints autoritativos en modo autoritativo.',
      },
    });
  }
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

  const rejected: Record<string, any[]> = {
    clients: [],
    sellers: [],
    products: [],
    sales: [],
    installments: [],
    payments: [],
  };

  const ack = {
    clients: await upsertClients(company.id, uploaded.clients, rejected.clients),
    sellers: await upsertSellers(company.id, uploaded.sellers, rejected.sellers),
    products: await upsertLots(company.id, uploaded.products, rejected.products),
    sales: await upsertSales(company.id, uploaded.sales, rejected.sales),
    installments: await upsertInstallments(company.id, uploaded.installments, rejected.installments),
    payments: await upsertPayments(company.id, uploaded.payments, rejected.payments, authUser?.id),
  };
  await recalculateSaleBalances(company.id, [
    ...uploaded.installments.map((row) => stringValue(row.sale_sync_id, row.venta_sync_id)),
    ...uploaded.payments.map((row) => stringValue(row.sale_sync_id, row.venta_sync_id)),
  ]);

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
    rejected: rejected,
  });
});

function hasFinancialSyncRecords(records: Record<string, Row[] | undefined>) {
  return [
    records.sales,
    records.installments,
    records.cuotas,
    records.payments,
  ].some((rows) => (rows?.length ?? 0) > 0);
}

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
  if (!value) return 0;
  const normalized = value.replace(/,/g, '');
  return Number.isFinite(Number(normalized)) ? Number(normalized) : 0;
}

function rawJson(row: Row): any {
  return row;
}

async function findBySyncId<T extends { id: string }>(
  delegate: { findFirst: (args: any) => Promise<T | null> },
  companyId: string,
  syncId?: string | null,
) {
  if (!syncId) return null;
  return delegate.findFirst({
    where: { companyId, syncId, deletedAt: null },
    select: { id: true },
  });
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

function uniqueSyncIds(values: Array<string | null>) {
  return [...new Set(values.filter((value): value is string => Boolean(value?.trim())))];
}

export function isBlockingActiveSaleForLotDelete(
  sale: { deletedAt?: unknown; status?: string | null } | null | undefined,
) {
  return Boolean(sale && !sale.deletedAt && sale.status !== 'cancelada');
}

export function shouldRejectLegacySaleDateChange(input: {
  existingSaleDate?: Date | null;
  incomingSaleDate?: Date | null;
  hasActiveInstallments: boolean;
}) {
  if (!input.hasActiveInstallments) {
    return false;
  }
  if (!input.existingSaleDate || !input.incomingSaleDate) {
    return false;
  }
  return input.existingSaleDate.getTime() !== input.incomingSaleDate.getTime();
}

/**
 * Campos de una cuota que, una vez creada por el servidor, pasan a ser de
 * PROPIEDAD DEL SERVIDOR. Un cliente Windows/PWA antiguo o un flujo offline NO
 * puede reescribirlos mediante `POST /sync/upload`.
 *
 * Cambiarlos requiere una operacion autoritativa explicita (recalendarizacion
 * aprobada), no un upload generico.
 */
export const LOCKED_INSTALLMENT_FIELDS = [
  'dueDate',
  'installmentNumber',
  'openingBalance',
  'principalAmount',
  'interestAmount',
  'totalAmount',
  'endingBalance',
  'saleSyncId',
] as const;

function numericLike(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const text = value.toString().trim();
  if (text === '' || !/^-?\d+(\.\d+)?$/.test(text)) return null;
  const parsed = Number(text);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * P0 PROPIEDAD DEL SERVIDOR — ESTADO FINANCIERO DE LA CUOTA.
 *
 * `paidAmount`, `paidPrincipalAmount`, `paidInterestAmount` y `status` NO son
 * datos del cliente: son la CONSECUENCIA de una operacion financiera. En el
 * camino autoritativo los produce `AuthoritativePaymentService` (que ademas
 * genera el calendario con `paidAmount = 0`) y en el legacy los deriva el
 * servidor.
 *
 * Por eso un snapshot generico (`POST /sync/upload`, scope `installments`) no
 * puede:
 *   - CREAR `paidAmount` (cuota nueva: arranque canonico en 0);
 *   - AUMENTAR `paidAmount` (evita un "cobrado" inventado por el cliente);
 *   - REDUCIR `paidAmount` (evita degradar dinero ya cobrado);
 *   - forzar `pagada` / `parcial` sin un `Payment` que lo respalde.
 *
 * Contrato: los valores del SERVIDOR siempre ganan; el snapshot solo aporta la
 * ESTRUCTURA (calendario/importes), que tiene sus propios guards
 * (`findLockedInstallmentFieldChanges`, `canonicalScheduleViolation`).
 *
 * La proteccion es INDEPENDIENTE de `version`: el cliente no puede
 * autoproclamarse autoridad enviando una version mayor o igual.
 *
 * El snapshot no se RECHAZA por esto: se IGNORA el campo financiero y se
 * responde ACK con el valor autoritativo, para que el cliente converja en vez
 * de quedar reintentando una fila que nunca puede "corregir".
 */
export const SERVER_OWNED_INSTALLMENT_FIELDS = [
  'paidAmount',
  'paidPrincipalAmount',
  'paidInterestAmount',
  'status',
] as const;

export type InstallmentFinancialSnapshot = {
  paidAmount?: unknown;
  paidPrincipalAmount?: unknown;
  paidInterestAmount?: unknown;
  status?: string | null;
  totalAmount?: unknown;
};

export type ServerOwnedInstallmentFinancials = {
  paidAmount: number;
  paidPrincipalAmount: number;
  paidInterestAmount: number;
  status: string | null;
  ignoredFields: string[];
};

/**
 * Estados terminales que NO afirman un estado de dinero (`ajustada`,
 * `cancelada`). Son la unica `status` que un snapshot puede aportar al CREAR
 * una cuota: no representan cobro y no inventan importes.
 */
function nonMoneyTerminalStatus(status?: string | null) {
  const resolved = resolvePersistedInstallmentStatus({
    storedStatus: status ?? null,
    paidAmount: 0,
    // `totalAmount: 1` evita la rama "sin saldo pendiente" de
    // `resolvePersistedInstallmentStatus`, que devolveria `pagada`; aqui solo
    // interesa saber si el estado es un terminal que no afirma dinero.
    totalAmount: 1,
  });
  return resolved === 'ajustada' || resolved === 'cancelada' ? resolved : null;
}

/**
 * Resuelve el estado financiero efectivo de una cuota y reporta que campos del
 * snapshot fueron ignorados por ser propiedad del servidor.
 */
export function resolveServerOwnedInstallmentFinancials(input: {
  existing?: InstallmentFinancialSnapshot | null;
  incoming: InstallmentFinancialSnapshot;
}): ServerOwnedInstallmentFinancials {
  const existing = input.existing ?? null;
  const financials = existing
    ? {
        paidAmount: numericLike(existing.paidAmount) ?? 0,
        paidPrincipalAmount: numericLike(existing.paidPrincipalAmount) ?? 0,
        paidInterestAmount: numericLike(existing.paidInterestAmount) ?? 0,
        // El estado del servidor se conserva; `resolveIncomingInstallmentStatus`
        // solo normaliza el atraso derivado (`vencida`), que nunca se persiste.
        status: resolveIncomingInstallmentStatus({
          incomingStatus: existing.status ?? null,
          paidAmount: existing.paidAmount ?? 0,
          totalAmount: existing.totalAmount ?? input.incoming.totalAmount,
        }),
      }
    : {
        // Cuota nueva: arranque canonico. El dinero entra como `Payment` y lo
        // aplica `AuthoritativePaymentService`.
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        status: nonMoneyTerminalStatus(input.incoming.status) ?? 'pendiente',
      };

  const ignoredFields: string[] = [];
  for (const field of SERVER_OWNED_INSTALLMENT_FIELDS) {
    const after = input.incoming[field];
    if (after === undefined || after === null) continue;
    if (!sameFinancialValue(financials[field], after)) ignoredFields.push(field);
  }

  return { ...financials, ignoredFields };
}

export function sameFinancialValue(before: unknown, after: unknown) {
  const dateBefore = before instanceof Date ? before.getTime() : null;
  const dateAfter = after instanceof Date ? after.getTime() : null;
  if (dateBefore !== null || dateAfter !== null) return dateBefore === dateAfter;

  const numBefore = numericLike(before);
  const numAfter = numericLike(after);
  if (numBefore !== null && numAfter !== null) {
    return Math.abs(numBefore - numAfter) <= 0.009;
  }
  if (before === null || before === undefined || after === null || after === undefined) {
    return (before ?? null) === (after ?? null);
  }
  return before.toString() === after.toString();
}

/** Devuelve los campos protegidos que el cliente intenta cambiar (vacio = OK). */
export function findLockedInstallmentFieldChanges(
  existing: Record<string, unknown> | null | undefined,
  incoming: Record<string, unknown>,
) {
  if (!existing) return [] as string[];
  const changed: string[] = [];
  for (const field of LOCKED_INSTALLMENT_FIELDS) {
    const after = incoming[field];
    if (after === undefined || after === null) continue;
    if (!sameFinancialValue(existing[field], after)) changed.push(field);
  }
  return changed;
}

/**
 * FASE 4 — INVARIANTE DEL SERVIDOR.
 *
 * Una cuota NUEVA enviada por un cliente debe cumplir la regla canonica
 * `dueDate(n) = saleDate + n meses`. Si no la cumple se RECHAZA con error
 * explicito: no se autocorrige en silencio un payload financiero ambiguo.
 *
 * Devuelve `null` cuando no hay violacion demostrable (p. ej. falta el ancla
 * `saleDate`, caso legado) o el motivo del rechazo cuando la hay.
 */
export function canonicalScheduleViolation(input: {
  saleDate?: Date | null;
  installmentNumber?: number | null;
  dueDate?: Date | null;
}) {
  if (!input.saleDate || !input.dueDate) return null;
  const number = input.installmentNumber;
  if (typeof number !== 'number' || !Number.isInteger(number) || number <= 0) return null;
  if (
    isCanonicalInstallmentDueDate({
      saleDate: input.saleDate,
      installmentNumber: number,
      dueDate: input.dueDate,
    })
  ) {
    return null;
  }
  return 'installment_due_date_not_canonical';
}

/**
 * FASE 7 — el atraso derivado (`vencida`) no se persiste.
 *
 * Si un cliente envia `vencida`/`overdue`/`atrasada`, el servidor persiste el
 * estado que depende de dinero (pagada / parcial / pendiente). Un cambio natural
 * de dia no debe convertirse en una escritura de sync.
 */
export function resolveIncomingInstallmentStatus(input: {
  incomingStatus?: string | null;
  paidAmount: unknown;
  totalAmount: unknown;
}) {
  if (!isTimeDerivedOverdueStatus(input.incomingStatus)) return input.incomingStatus ?? null;
  const total = numericLike(input.totalAmount);
  const paid = numericLike(input.paidAmount) ?? 0;
  if (total === null || total <= 0.009) {
    // Sin monto no se puede derivar un estado financiero: se conserva el enviado
    // (no se inventa `pagada` para una cuota sin importe).
    return input.incomingStatus ?? null;
  }
  return resolvePersistedInstallmentStatus({
    storedStatus: input.incomingStatus,
    paidAmount: paid,
    totalAmount: total,
  });
}

export function describeCanonicalDueDate(input: {
  saleDate?: Date | null;
  installmentNumber?: number | null;
}) {
  if (!input.saleDate || !input.installmentNumber) return null;
  return canonicalInstallmentDueDate(input.saleDate, input.installmentNumber).toISOString();
}

async function upsertClients(companyId: string, rows: Row[], rejected: any[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const document = stringValue(row.cedula, row.document_id, row.document);
    const data = {
      name: stringValue(row.nombre, row.name, row.full_name) ?? 'Sin nombre',
      document,
      phone: stringValue(row.telefono, row.phone),
      address: stringValue(row.direccion, row.address),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };

    // Validar duplicado activo por documento (solo si tiene documento y no es deleted)
    if (document && document.trim().length > 0 && !data.deletedAt) {
      const existingActive = await prisma.client.findFirst({
        where: {
          companyId,
          document,
          deletedAt: null,
          syncId: { not: id },
        },
        select: { id: true, syncId: true },
      });
      if (existingActive) {
        console.log(
          `[DuplicateCheck][Client] companyId=${companyId} document=${document} foundActive=true -> rejected (existing syncId=${existingActive.syncId})`,
        );
        rejected.push({
          sync_id: id,
          reason: 'active_duplicate',
          message: 'Ya existe un cliente activo con este documento',
          existingSyncId: existingActive.syncId,
        });
        continue;
      }
    }

    const saved = await prisma.client.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(clientRecord(saved));
  }
  return ack;
}

async function upsertSellers(companyId: string, rows: Row[], rejected: any[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const document = stringValue(row.cedula, row.document_id, row.document);
    const data = {
      name: stringValue(row.nombre, row.name, row.full_name) ?? 'Sin nombre',
      document,
      phone: stringValue(row.telefono, row.phone),
      active: String(row.activo ?? row.active ?? 'true') !== 'false',
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };

    // Validar duplicado activo por documento (solo si tiene documento y no es deleted)
    if (document && document.trim().length > 0 && !data.deletedAt) {
      const existingActive = await prisma.seller.findFirst({
        where: {
          companyId,
          document,
          deletedAt: null,
          syncId: { not: id },
        },
        select: { id: true, syncId: true },
      });
      if (existingActive) {
        console.log(
          `[DuplicateCheck][Seller] companyId=${companyId} document=${document} foundActive=true -> rejected (existing syncId=${existingActive.syncId})`,
        );
        rejected.push({
          sync_id: id,
          reason: 'active_duplicate',
          message: 'Ya existe un vendedor activo con este documento',
          existingSyncId: existingActive.syncId,
        });
        continue;
      }
    }

    const saved = await prisma.seller.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(sellerRecord(saved));
  }
  return ack;
}

async function upsertLots(companyId: string, rows: Row[], rejected: any[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const block = stringValue(row.block_number, row.manzana_numero, row.block, row.manzana);
    const number = stringValue(row.lot_number, row.solar_numero, row.number, row.numero);
    const data = {
      block,
      number,
      status: stringValue(row.status, row.estado),
      area: decimalValue(row.area, row.metros_cuadrados),
      price: decimalValue(row.price_per_square_meter, row.precio_por_metro, row.price),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };

    if (data.deletedAt) {
      const existingLot = await prisma.lot.findUnique({
        where: { companyId_syncId: { companyId, syncId: id } },
        select: { id: true, syncId: true },
      });
      if (existingLot) {
        const activeSale = await prisma.sale.findFirst({
          where: {
            companyId,
            lotId: existingLot.id,
            deletedAt: null,
            NOT: { status: 'cancelada' },
          },
          select: { id: true, syncId: true, status: true, deletedAt: true },
        });
        if (activeSale && isBlockingActiveSaleForLotDelete(activeSale)) {
          console.log(
            `[IntegrityCheck][LotDelete] companyId=${companyId} syncId=${id} activeSale=${activeSale.syncId} -> rejected`,
          );
          rejected.push({
            sync_id: id,
            reason: 'active_sale_reference',
            message: 'No se puede eliminar un solar con una venta activa.',
            existingSaleSyncId: activeSale.syncId,
          });
          continue;
        }
      }
    }

    // Validar duplicado activo por block+number (solo si no es deleted)
    if (block && block.trim().length > 0 && number && number.trim().length > 0 && !data.deletedAt) {
      const existingActive = await prisma.lot.findFirst({
        where: {
          companyId,
          block,
          number,
          deletedAt: null,
          syncId: { not: id },
        },
        select: { id: true, syncId: true },
      });
      if (existingActive) {
        console.log(
          `[DuplicateCheck][Lot] companyId=${companyId} block=${block} number=${number} foundActive=true -> rejected (existing syncId=${existingActive.syncId})`,
        );
        rejected.push({
          sync_id: id,
          reason: 'active_duplicate',
          message: `Ya existe un solar activo con block=${block} number=${number}`,
          existingSyncId: existingActive.syncId,
        });
        continue;
      }
    }

    const saved = await prisma.lot.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data },
      update: data,
    });
    ack.push(lotRecord(saved));
  }
  return ack;
}

async function upsertSales(companyId: string, rows: Row[], rejected: any[]) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      lotSyncId: stringValue(row.product_sync_id, row.lot_sync_id, row.solar_sync_id),
      sellerSyncId: stringValue(row.seller_sync_id, row.vendedor_sync_id),
      operatorUserSyncId: stringValue(row.user_sync_id, row.usuario_sync_id, row.operator_user_sync_id),
      saleDate: dateValue(row.sale_date ?? row.fecha_venta),
      status: stringValue(row.status, row.estado),
      total: decimalValue(row.sale_price, row.precio_venta, row.total),
      initialPercentage: stringValue(row.down_payment_percentage, row.inicial_porcentaje, row.initialPercentage)
        ? decimalValue(row.down_payment_percentage, row.inicial_porcentaje, row.initialPercentage)
        : null,
      initialRequiredAmount: decimalValue(row.required_initial_payment, row.monto_inicial_requerido),
      initialPaid: decimalValue(row.paid_initial_payment, row.monto_inicial_pagado, row.inicial, row.initialPaid),
      initialPendingAmount: decimalValue(row.pending_initial_payment, row.monto_inicial_pendiente),
      reservationMinimumAmount: decimalValue(row.minimum_reserve_amount, row.monto_apartado_minimo),
      reservationPaidAmount: decimalValue(row.reserve_paid_amount, row.monto_apartado_pagado),
      initialPaymentDeadline: dateValue(row.initial_payment_deadline ?? row.fecha_limite_inicial),
      activationDate: dateValue(row.activation_date ?? row.fecha_activacion),
      financedBalance: decimalValue(row.financed_balance, row.saldo_financiado),
      monthlyInterestRate: stringValue(row.monthly_interest, row.interes_mensual)
        ? decimalValue(row.monthly_interest, row.interes_mensual)
        : null,
      installmentCount: intValue(row.installment_count ?? row.cantidad_cuotas),
      balance: decimalValue(row.pending_balance, row.saldo_pendiente, row.balance),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const relationIds = {
      clientId: null as string | null,
      lotId: null as string | null,
      sellerId: null as string | null,
      operatorUserId: null as string | null,
    };

    // Validar dependencias solo si no es soft delete
    if (!data.deletedAt) {
      const missingDeps: string[] = [];

      if (data.clientSyncId) {
        const client = await findBySyncId(prisma.client, companyId, data.clientSyncId);
        if (!client) missingDeps.push('clientSyncId');
        relationIds.clientId = client?.id ?? null;
      }

      if (data.lotSyncId) {
        const lot = await findBySyncId(prisma.lot, companyId, data.lotSyncId);
        if (!lot) missingDeps.push('lotSyncId');
        relationIds.lotId = lot?.id ?? null;
      }

      if (data.sellerSyncId) {
        const seller = await findBySyncId(prisma.seller, companyId, data.sellerSyncId);
        if (!seller) missingDeps.push('sellerSyncId');
        relationIds.sellerId = seller?.id ?? null;
      }

      if (data.operatorUserSyncId) {
        const operator = await findBySyncId(prisma.user, companyId, data.operatorUserSyncId);
        relationIds.operatorUserId = operator?.id ?? null;
      }

      if (missingDeps.length > 0) {
        console.log(
          `[DependencyCheck][Sale] companyId=${companyId} syncId=${id} missing=${missingDeps.join(',')} -> rejected`,
        );
        rejected.push({
          sync_id: id,
          reason: 'missing_dependency',
          message: `Dependencias faltantes: ${missingDeps.join(', ')}`,
          missingFields: missingDeps,
        });
        continue;
      }
    }

    const existingSale = await prisma.sale.findUnique({
      where: { companyId_syncId: { companyId, syncId: id } },
      select: {
        id: true,
        saleDate: true,
        installments: {
          where: { deletedAt: null },
          select: { id: true },
          take: 1,
        },
      },
    });

    if (
      shouldRejectLegacySaleDateChange({
        existingSaleDate: existingSale?.saleDate ?? null,
        incomingSaleDate: data.saleDate,
        hasActiveInstallments:
          (existingSale?.installments.length ?? 0) > 0,
      })
    ) {
      rejected.push({
        sync_id: id,
        reason: 'sale_date_edit_requires_admin_recalendarization',
        message:
          'No se puede sincronizar un cambio de fecha de venta con cuotas activas. Requiere recalendarizacion administrativa explicita.',
      });
      continue;
    }

    const saved = await prisma.sale.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data, ...relationIds },
      update: { ...data, ...relationIds },
    });
    ack.push(saleRecord(saved));
  }
  return ack;
}

async function upsertInstallments(companyId: string, rows: Row[], rejected: any[]) {
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
    let saleId: string | null = null;
    let saleRecord: any = null;

    // Validar dependencia saleSyncId solo si no es soft delete
    if (!data.deletedAt && data.saleSyncId) {
      const sale = await findBySyncId(prisma.sale, companyId, data.saleSyncId);
      saleId = sale?.id ?? null;
      saleRecord = sale ?? null;
      if (!sale) {
        console.log(
          `[DependencyCheck][Installment] companyId=${companyId} syncId=${id} missing=saleSyncId -> rejected`,
        );
        rejected.push({
          sync_id: id,
          reason: 'missing_dependency',
          message: 'La venta referenciada (saleSyncId) no existe o no está activa',
          missingFields: ['saleSyncId'],
        });
        continue;
      }
    }

    const existing = await prisma.installment.findUnique({
      where: { companyId_syncId: { companyId, syncId: id } },
      select: {
        id: true,
        dueDate: true,
        installmentNumber: true,
        openingBalance: true,
        principalAmount: true,
        interestAmount: true,
        totalAmount: true,
        paidAmount: true,
        paidPrincipalAmount: true,
        paidInterestAmount: true,
        endingBalance: true,
        saleSyncId: true,
        status: true,
      },
    });

    // FASE 6 — una cuota ya propiedad del servidor no puede ser reescrita por un
    // cliente legacy/offline (calendario, numeración o importes).
    const lockedChanges = findLockedInstallmentFieldChanges(
      existing as unknown as Record<string, unknown> | null,
      data as unknown as Record<string, unknown>,
    );
    if (lockedChanges.length > 0) {
      console.log(
        `[Ownership][Installment] companyId=${companyId} syncId=${id} lockedFields=${lockedChanges.join(',')} -> rejected`,
      );
      rejected.push({
        sync_id: id,
        reason: 'installment_field_locked',
        message:
          'La cuota ya existe en la nube: dueDate, numero, importes y ancla de venta no pueden modificarse por sync genérico.',
        lockedFields: lockedChanges,
      });
      continue;
    }

    // P0 PROPIEDAD DEL SERVIDOR — el estado financiero de la cuota no viaja en
    // el snapshot generico. Ver `resolveServerOwnedInstallmentFinancials`.
    // Si el cliente manda importes/estado financieros distintos, se IGNORAN
    // (no se rechaza la fila) y el ACK devuelve el valor autoritativo.
    const serverFinancials = resolveServerOwnedInstallmentFinancials({
      existing,
      incoming: data,
    });
    if (serverFinancials.ignoredFields.length > 0) {
      console.log(
        `[Ownership][Installment] companyId=${companyId} syncId=${id} serverOwnedIgnored=${serverFinancials.ignoredFields.join(',')} -> acked with server values`,
      );
    }

    // FASE 4 — cuota nueva: el calendario enviado debe cumplir la regla canónica
    // dueDate(n) = saleDate + n meses. No se autocorrige en silencio.
    if (!existing) {
      const violation = canonicalScheduleViolation({
        saleDate: saleRecord?.saleDate ?? null,
        installmentNumber: data.installmentNumber,
        dueDate: data.dueDate,
      });
      if (violation) {
        const expected = describeCanonicalDueDate({
          saleDate: saleRecord?.saleDate ?? null,
          installmentNumber: data.installmentNumber,
        });
        console.log(
          `[CanonicalSchedule][Installment] companyId=${companyId} syncId=${id} expected=${expected} -> rejected`,
        );
        rejected.push({
          sync_id: id,
          reason: violation,
          message:
            'La fecha de vencimiento enviada no cumple la regla del producto: dueDate(n) = saleDate + n meses.',
          expectedDueDate: expected,
        });
        continue;
      }
    }

    const saved = await prisma.installment.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: {
        companyId,
        syncId: id,
        ...data,
        paidAmount: serverFinancials.paidAmount,
        paidPrincipalAmount: serverFinancials.paidPrincipalAmount,
        paidInterestAmount: serverFinancials.paidInterestAmount,
        status: serverFinancials.status,
        saleId,
      },
      update: {
        ...data,
        paidAmount: serverFinancials.paidAmount,
        paidPrincipalAmount: serverFinancials.paidPrincipalAmount,
        paidInterestAmount: serverFinancials.paidInterestAmount,
        status: serverFinancials.status,
        saleId,
      },
    });
    ack.push(installmentRecord(saved));
  }
  return ack;
}

async function upsertPayments(
  companyId: string,
  rows: Row[],
  rejected: any[],
  authenticatedUserId?: string,
) {
  const ack: Row[] = [];
  for (const row of rows) {
    const id = syncId(row);
    if (!id) continue;
    const data = {
      saleSyncId: stringValue(row.sale_sync_id, row.venta_sync_id),
      clientSyncId: stringValue(row.client_sync_id, row.cliente_sync_id),
      installmentSyncId: stringValue(row.installment_sync_id, row.cuota_sync_id),
      receivedByUserSyncId: stringValue(row.user_sync_id, row.usuario_sync_id, row.received_by_user_sync_id),
      paidAt: dateValue(row.payment_date ?? row.fecha_pago ?? row.paidAt),
      amount: decimalValue(row.amount_paid, row.monto_pagado, row.amount),
      method: stringValue(row.payment_method, row.metodo_pago, row.method),
      paymentType: stringValue(row.payment_type, row.tipo_pago),
      reference: stringValue(row.reference, row.referencia),
      yearToPay: intValue(row.year_to_pay ?? row.ano_a_pagar),
      principalApplied: decimalValue(row.principal_applied, row.capital_aplicado),
      interestApplied: decimalValue(row.interest_applied, row.interes_aplicado),
      lateFeeApplied: decimalValue(row.late_fee_applied, row.mora_aplicada),
      annulledAt: dateValue(row.annulled_at ?? row.anulado_en),
      annulmentReason: stringValue(row.annulment_reason, row.motivo_anulacion),
      raw: rawJson(row),
      version: versionValue(row),
      deletedAt: deletedAt(row),
    };
    const relationIds = {
      saleId: null as string | null,
      clientId: null as string | null,
      installmentId: null as string | null,
      receivedByUserId: null as string | null,
    };

    // Validar dependencias solo si no es soft delete
    if (!data.deletedAt) {
      const missingDeps: string[] = [];

      if (data.saleSyncId) {
        const sale = await findBySyncId(prisma.sale, companyId, data.saleSyncId);
        if (!sale) missingDeps.push('saleSyncId');
        relationIds.saleId = sale?.id ?? null;
      }

      if (data.clientSyncId) {
        const client = await findBySyncId(prisma.client, companyId, data.clientSyncId);
        if (!client) missingDeps.push('clientSyncId');
        relationIds.clientId = client?.id ?? null;
      }

      if (data.installmentSyncId) {
        const installment = await findBySyncId(prisma.installment, companyId, data.installmentSyncId);
        if (!installment) missingDeps.push('installmentSyncId');
        relationIds.installmentId = installment?.id ?? null;
      }

      if (data.receivedByUserSyncId) {
        const user = await findBySyncId(prisma.user, companyId, data.receivedByUserSyncId);
        relationIds.receivedByUserId = user?.id ?? null;
      }

      // El fallback de usuario solo se consulta cuando las referencias estan
      // completas (mismo orden de trabajo que antes de extraer la decision).
      let receivedByUserId = relationIds.receivedByUserId ?? authenticatedUserId ?? null;
      if (missingDeps.length === 0 && !receivedByUserId) {
        receivedByUserId = await resolveFallbackUserId(companyId);
      }

      const decision = resolvePaymentUploadRoute({
        syncId: id,
        deletedAt: null,
        missingDependencies: missingDeps,
        hasReceivedByUser: receivedByUserId !== null,
      });
      if (decision.route === 'reject') {
        console.log(
          `[DependencyCheck][Payment] companyId=${companyId} syncId=${id} missing=${decision.missingFields.join(',')} -> rejected`,
        );
        rejected.push({
          sync_id: id,
          reason: decision.reason,
          message: decision.message,
          missingFields: decision.missingFields,
        });
        continue;
      }

      // El contrato de `resolvePaymentUploadRoute` garantiza que aqui hay usuario
      // receptor: solo la ruta `authoritative` llega a este punto.
      const resolvedReceivedByUserId = receivedByUserId as string;

      try {
        const result = await authoritativePayments.registerPayment({
          companyId,
          receivedByUserId: resolvedReceivedByUserId,
          idempotencyKey: offlinePaymentIdempotencyKey(companyId, id),
          saleSyncId: data.saleSyncId ?? undefined,
          paymentDate: data.paidAt ?? undefined,
          amountPaid: data.amount,
          paymentMethod: data.method,
          paymentType: data.paymentType,
          paymentTypeOverride: data.paymentType,
          yearToPay: data.yearToPay,
          reference: data.reference,
          sourceSyncId: id,
        });

        const paymentIds = Array.isArray(result.response.paymentIds)
          ? result.response.paymentIds.map((value) => String(value))
          : [];
        if (paymentIds.length === 0) {
          rejected.push({
            sync_id: id,
            reason: 'authoritative_payment_without_rows',
            message: 'La operacion autoritativa no devolvio filas de pago.',
          });
          continue;
        }

        const saved = await prisma.payment.findMany({
          where: { companyId, id: { in: paymentIds } },
          orderBy: { paidAt: 'asc' },
        });
        ack.push(...saved.map(paymentRecord));
        continue;
      } catch (error) {
        const response = authoritativeErrorResponse(error);
        rejected.push({
          sync_id: id,
          reason: response.body.error.code,
          message: response.body.error.message,
        });
        continue;
      }
    }

    const saved = await prisma.payment.upsert({
      where: { companyId_syncId: { companyId, syncId: id } },
      create: { companyId, syncId: id, ...data, ...relationIds },
      update: { ...data, ...relationIds },
    });
    ack.push(paymentRecord(saved));
  }
  return ack;
}

export function offlinePaymentIdempotencyKey(companyId: string, sourceSyncId: string) {
  return `offline-payment:${companyId}:${sourceSyncId}`;
}

/**
 * P0 BRIDGE FINANCIERO — ruta de aplicacion de un `payments` del upload.
 *
 * Un pago VALIDO nunca entra como snapshot: entra por
 * `AuthoritativePaymentService.registerPayment`, que aplica las reglas
 * financieras, actualiza cuota/venta y es idempotente. El upsert crudo queda
 * solo para tombstones (soft delete), que no mueven dinero.
 *
 * Contrato:
 *  - `skip`: fila sin `sync_id` (no hay identidad que confirmar).
 *  - `legacy_tombstone`: soft delete (no aplica reglas financieras).
 *  - `reject`: referencias faltantes => NO se escribe nada y NO se hace ACK
 *    (el cliente lo ve como no confirmado y aplica su retry acotado).
 *  - `authoritative`: pago financiero valido.
 */
export type PaymentUploadRoute =
  | { route: 'skip' }
  | { route: 'legacy_tombstone' }
  | {
      route: 'reject';
      reason: 'missing_dependency';
      message: string;
      missingFields: string[];
    }
  | { route: 'authoritative' };

export function resolvePaymentUploadRoute(input: {
  syncId?: string | null;
  deletedAt?: Date | null;
  missingDependencies?: string[];
  hasReceivedByUser?: boolean;
}): PaymentUploadRoute {
  if (!input.syncId || !input.syncId.trim()) return { route: 'skip' };
  if (input.deletedAt) return { route: 'legacy_tombstone' };

  const missingFields = input.missingDependencies ?? [];
  if (missingFields.length > 0) {
    return {
      route: 'reject',
      reason: 'missing_dependency',
      message: `Dependencias faltantes: ${missingFields.join(', ')}`,
      missingFields: [...missingFields],
    };
  }
  if (!input.hasReceivedByUser) {
    return {
      route: 'reject',
      reason: 'missing_dependency',
      message: 'No se pudo resolver el usuario receptor del pago.',
      missingFields: ['receivedByUserId'],
    };
  }
  return { route: 'authoritative' };
}

async function resolveFallbackUserId(companyId: string) {
  const user = await prisma.user.findFirst({
    where: { companyId, deletedAt: null, active: true },
    orderBy: { createdAt: 'asc' },
    select: { id: true },
  });
  return user?.id ?? null;
}

async function recalculateSaleBalances(companyId: string, saleSyncIds: Array<string | null>) {
  const uniqueSaleSyncIds = uniqueSyncIds(saleSyncIds);
  for (const saleSyncId of uniqueSaleSyncIds) {
    const installments = await prisma.installment.findMany({
      where: {
        companyId,
        saleSyncId,
        deletedAt: null,
        status: { not: 'ajustada' },
      },
      select: {
        principalAmount: true,
        paidPrincipalAmount: true,
        status: true,
      },
    });
    if (installments.length === 0) {
      continue;
    }

    const balance = installments.reduce((total, installment) => {
      if (installment.status === 'cancelada') return total;
      const principal = Number(installment.principalAmount ?? 0);
      const paidPrincipal = Number(installment.paidPrincipalAmount ?? 0);
      return total + Math.max(principal - paidPrincipal, 0);
    }, 0);

    await prisma.sale.updateMany({
      where: { companyId, syncId: saleSyncId, deletedAt: null },
      data: {
        balance,
        status: balance <= 0.009 ? 'pagada' : 'activa',
      },
    });
  }
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
    user_sync_id: row.operatorUserSyncId,
    sale_date: row.saleDate?.toISOString() ?? null,
    status: row.status,
    sale_price: row.total?.toString() ?? '0',
    total: row.total?.toString() ?? '0',
    down_payment_percentage: row.initialPercentage?.toString() ?? null,
    required_initial_payment: row.initialRequiredAmount?.toString() ?? '0',
    paid_initial_payment: row.initialPaid?.toString() ?? '0',
    initial_paid: row.initialPaid?.toString() ?? '0',
    pending_initial_payment: row.initialPendingAmount?.toString() ?? '0',
    minimum_reserve_amount: row.reservationMinimumAmount?.toString() ?? '0',
    reserve_paid_amount: row.reservationPaidAmount?.toString() ?? '0',
    initial_payment_deadline: row.initialPaymentDeadline?.toISOString() ?? null,
    activation_date: row.activationDate?.toISOString() ?? null,
    financed_balance: row.financedBalance?.toString() ?? '0',
    monthly_interest: row.monthlyInterestRate?.toString() ?? null,
    installment_count: row.installmentCount,
    pending_balance: row.balance?.toString() ?? '0',
    saldo_pendiente: row.balance?.toString() ?? '0',
    balance: row.balance?.toString() ?? '0',
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

/**
 * Extrae la INTENCION de origen de un Payment autoritativo
 * (`raw.sourceSyncId`). Devuelve `null` para pagos creados online directo.
 * Solo transforma datos: no aplica ninguna regla financiera.
 */
export function readRawSourceSyncId(raw: unknown): string | null {
  if (!raw || typeof raw !== 'object') return null;
  const value = (raw as Record<string, unknown>).sourceSyncId;
  if (value === null || value === undefined) return null;
  const text = value.toString().trim();
  return text === '' ? null : text;
}

function paymentRecord(row: any): Row {
  return {
    id: row.id,
    sync_id: row.syncId,
    version: row.version,
    sale_sync_id: row.saleSyncId,
    client_sync_id: row.clientSyncId,
    installment_sync_id: row.installmentSyncId,
    // P0 IDENTIDAD: correlacion intencion offline -> fila autoritativa.
    source_payment_sync_id: readRawSourceSyncId(row.raw),
    user_sync_id: row.receivedByUserSyncId,
    payment_date: row.paidAt?.toISOString() ?? null,
    amount_paid: row.amount?.toString() ?? '0',
    payment_method: row.method,
    payment_type: row.paymentType,
    reference: row.reference,
    year_to_pay: row.yearToPay,
    principal_applied: row.principalApplied?.toString() ?? '0',
    interest_applied: row.interestApplied?.toString() ?? '0',
    late_fee_applied: row.lateFeeApplied?.toString() ?? '0',
    annulled_at: row.annulledAt?.toISOString() ?? null,
    annulment_reason: row.annulmentReason,
    created_at: row.createdAt?.toISOString(),
    updated_at: row.updatedAt?.toISOString(),
    deleted_at: row.deletedAt?.toISOString() ?? null,
  };
}
