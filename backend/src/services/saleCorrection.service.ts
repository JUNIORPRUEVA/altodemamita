import { Prisma, PrismaClient } from "@prisma/client";
import { AuthoritativeError } from "./authoritativeErrors.service";
import {
  buildInstallmentSchedule,
  calculateFinancedBalance,
  calculatePendingInitialPayment,
  canonicalInstallmentDueDates,
  resolveUpfrontSaleStatus,
  roundCurrency,
} from "./financing.service";
import { decimal, newSyncId, parseDate, toNumber } from "./authoritativeSale.service";
import {
  IdempotentResult,
  requireIdempotencyKey,
  runIdempotentOperation,
} from "./idempotency.service";
import {
  loadActiveInstallments,
  lockSaleForFinancialMutation,
} from "./authoritativePayment.service";
import { cancelSaleInTransaction } from "./authoritativeSale.service";

/**
 * FASE 03 — Administracion OWNER de VENTAS y CONTRATOS.
 *
 * Reglas de integridad (se validan SIEMPRE, en preview y en apply):
 *
 *  S1. Una venta con PAGOS ACTIVOS no puede cambiar importes, cliente, lote ni
 *      fecha de venta: primero se anulan los pagos (01C) o se corrige la cuota
 *      (02). Asi la historia de pagos nunca queda huerfana.
 *  S2. `Sale.balance` == capital pendiente de las cuotas activas.
 *  S3. Un solar no puede pertenecer a dos ventas activas.
 *  S4. Cancelar no borra nada: el cronograma se marca `cancelada`+`deletedAt` y
 *      la venta se marca `cancelada`, guardando un snapshot para poder restaurar.
 *  S5. Restaurar exige snapshot y que el solar siga libre.
 *  S6. Toda operacion es atomica, idempotente, con bloqueo de venta, version
 *      optimista y auditoria en `Sale.raw.corrections` + AuthoritativeOperation.
 */

export type SaleCorrectionAction =
  | "update_financing"
  | "change_client"
  | "change_lot"
  | "cancel"
  | "restore";

const ACTIONS: readonly SaleCorrectionAction[] = [
  "update_financing",
  "change_client",
  "change_lot",
  "cancel",
  "restore",
];

export function isSaleCorrectionAction(
  value: unknown,
): value is SaleCorrectionAction {
  return typeof value === "string" && (ACTIONS as readonly string[]).includes(value);
}

export type SaleCorrectionInput = {
  companyId: string;
  saleId: string;
  action: SaleCorrectionAction;
  /** update_financing */
  saleDate?: string | Date | null;
  totalPrice?: number | null;
  initialPaidAmount?: number | null;
  initialRequiredAmount?: number | null;
  installmentCount?: number | null;
  monthlyInterestRate?: number | null;
  initialPaymentDeadline?: string | Date | null;
  /** change_client / change_lot */
  clientId?: string | null;
  lotId?: string | null;
};

export type ApplySaleCorrectionInput = SaleCorrectionInput & {
  performedByUserId: string;
  reason: string;
  idempotencyKey: string;
  expectedSaleVersion?: number | null;
};

export const OPEN_INSTALLMENT_STATUSES = [
  "pendiente",
  "parcial",
  "vencida",
  "inicial_incompleto",
];

/** Valida los parametros de financiamiento antes de tocar nada. */
export function validateFinancing(input: {
  totalPrice: number;
  initialPaidAmount: number;
  initialRequiredAmount: number;
  installmentCount: number;
  monthlyInterestRate: number;
}): { code: string; message: string } | null {
  if (!Number.isFinite(input.totalPrice) || input.totalPrice <= 0) {
    return {
      code: "INVALID_SALE_PRICE",
      message: "El precio de la venta debe ser mayor que cero.",
    };
  }
  if (
    !Number.isFinite(input.initialPaidAmount) ||
    input.initialPaidAmount < 0 ||
    input.initialPaidAmount > input.totalPrice + 0.009
  ) {
    return {
      code: "INVALID_INITIAL_PAID",
      message: "La inicial pagada no puede ser negativa ni superar el precio de la venta.",
    };
  }
  if (
    !Number.isFinite(input.initialRequiredAmount) ||
    input.initialRequiredAmount < 0 ||
    input.initialRequiredAmount > input.totalPrice + 0.009
  ) {
    return {
      code: "INVALID_REQUIRED_INITIAL",
      message: "La inicial requerida no puede ser negativa ni superar el precio de la venta.",
    };
  }
  if (
    !Number.isInteger(input.installmentCount) ||
    input.installmentCount < 0 ||
    input.installmentCount > 120
  ) {
    return {
      code: "INVALID_INSTALLMENT_COUNT",
      message: "El plazo debe ser un numero entero entre 0 y 120 cuotas.",
    };
  }
  if (
    !Number.isFinite(input.monthlyInterestRate) ||
    input.monthlyInterestRate < 0 ||
    input.monthlyInterestRate > 100
  ) {
    return {
      code: "INVALID_INTEREST_RATE",
      message: "La tasa mensual debe estar entre 0 y 100.",
    };
  }
  const financed = roundCurrency(input.totalPrice - input.initialPaidAmount);
  if (financed > 0.009 && input.installmentCount < 1) {
    return {
      code: "INSTALLMENTS_REQUIRED",
      message: "Si queda saldo financiado debes indicar al menos una cuota.",
    };
  }
  return null;
}

export function saleStatusFor(input: {
  initialRequiredAmount: number;
  initialPaidAmount: number;
  financedBalance: number;
}) {
  return resolveUpfrontSaleStatus({
    initialRequiredAmount: input.initialRequiredAmount,
    initialPaidAmount: input.initialPaidAmount,
    financedBalance: input.financedBalance,
  });
}

function appendSaleAudit(
  raw: unknown,
  entry: Record<string, unknown>,
): Record<string, unknown> {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  const previous = Array.isArray(base.corrections)
    ? (base.corrections as unknown[])
    : [];
  base.corrections = [...previous, entry].slice(-30);
  return base;
}

type Tx = Prisma.TransactionClient;

async function loadSale(tx: Tx, companyId: string, saleId: string) {
  const sale = await tx.sale.findFirst({
    where: { id: saleId, companyId },
    include: {
      lot: true,
      client: true,
      payments: {
        where: { deletedAt: null, annulledAt: null },
        select: { id: true },
      },
    },
  });
  if (!sale) {
    throw new AuthoritativeError(
      "SALE_NOT_FOUND",
      "La venta seleccionada no existe.",
      404,
    );
  }
  return sale;
}

async function assertLotFree(
  tx: Tx,
  companyId: string,
  lotId: string,
  exceptSaleId: string,
) {
  const conflict = await tx.sale.findFirst({
    where: {
      companyId,
      lotId,
      deletedAt: null,
      id: { not: exceptSaleId },
      status: { notIn: ["cancelada"] },
    },
    select: { id: true, syncId: true },
  });
  if (conflict) {
    throw new AuthoritativeError(
      "LOT_ALREADY_ASSIGNED",
      "Ese solar ya pertenece a otra venta activa. Anula o cancela esa venta primero.",
      409,
    );
  }
}

export class SaleCorrectionService {
  constructor(private readonly prisma: PrismaClient) {}

  /** Previsualizacion exacta: igual logica dentro de una transaccion revertida. */
  async previewSaleCorrection(
    input: SaleCorrectionInput,
  ): Promise<Prisma.JsonObject> {
    if (!isSaleCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de venta no soportada.",
        400,
      );
    }
    const PREVIEW = Symbol("preview-rollback");
    try {
      await this.prisma.$transaction(async (tx) => {
        const result = await runCorrection(tx, input, {
          performedByUserId: "preview",
          reason: "preview",
          persistAudit: false,
        });
        throw { [PREVIEW]: true, result };
      });
    } catch (error: any) {
      if (error && error[PREVIEW]) {
        return { ...error.result, preview: true } as unknown as Prisma.JsonObject;
      }
      throw error;
    }
    throw new AuthoritativeError(
      "PREVIEW_FAILED",
      "No se pudo calcular la previsualizacion.",
      500,
    );
  }

  async applySaleCorrection(
    input: ApplySaleCorrectionInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    if (!isSaleCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de venta no soportada.",
        400,
      );
    }
    const reason = String(input.reason ?? "").trim();
    if (!reason) {
      throw new AuthoritativeError(
        "CORRECTION_REASON_REQUIRED",
        "Indica el motivo de la correccion de la venta.",
        400,
      );
    }
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: `sale.correction.${input.action}`,
        requestPayload: {
          saleId: input.saleId,
          action: input.action,
          saleDate: input.saleDate ?? null,
          totalPrice: input.totalPrice ?? null,
          initialPaidAmount: input.initialPaidAmount ?? null,
          initialRequiredAmount: input.initialRequiredAmount ?? null,
          installmentCount: input.installmentCount ?? null,
          monthlyInterestRate: input.monthlyInterestRate ?? null,
          initialPaymentDeadline: input.initialPaymentDeadline ?? null,
          clientId: input.clientId ?? null,
          lotId: input.lotId ?? null,
          reason,
          performedByUserId: input.performedByUserId,
        },
        run: async () => {
          const before = await loadSale(tx, input.companyId, input.saleId);
          await lockSaleForFinancialMutation(tx, before.id);
          const locked = await loadSale(tx, input.companyId, input.saleId);
          if (
            input.expectedSaleVersion != null &&
            locked.version !== input.expectedSaleVersion
          ) {
            throw new AuthoritativeError(
              "SALE_VERSION_CONFLICT",
              "La venta cambio desde que abriste el dialogo. Recarga e intentalo de nuevo.",
              409,
            );
          }
          const result = await runCorrection(tx, input, {
            performedByUserId: input.performedByUserId,
            reason,
            persistAudit: true,
          });
          return {
            response: {
              ...result,
              correction: {
                action: input.action,
                reason,
                performedByUserId: input.performedByUserId,
                performedAt: new Date().toISOString(),
              },
            } as unknown as Prisma.JsonObject,
            resourceType: "sale",
            resourceId: before.id,
          };
        },
      }),
    );
  }

  /** Auditoria de solo lectura de las correcciones de venta. */
  async getSaleCorrectionHistory(input: {
    companyId: string;
    saleId: string;
  }): Promise<Prisma.JsonObject> {
    const sale = await this.prisma.sale.findFirst({
      where: { id: input.saleId, companyId: input.companyId },
      select: { id: true, status: true, total: true, balance: true, raw: true, version: true },
    });
    if (!sale) {
      throw new AuthoritativeError(
        "SALE_NOT_FOUND",
        "La venta seleccionada no existe.",
        404,
      );
    }
    const operations = await this.prisma.authoritativeOperation.findMany({
      where: {
        companyId: input.companyId,
        resourceId: sale.id,
        operationType: { startsWith: "sale.correction." },
      },
      select: { operationType: true, createdAt: true, response: true },
      orderBy: { createdAt: "asc" },
    });

    type Entry = Record<string, unknown>;
    const history: Entry[] = [];
    const raw = (sale.raw ?? {}) as Record<string, unknown>;
    if (Array.isArray(raw.corrections)) {
      for (const entry of raw.corrections as unknown[]) {
        if (entry && typeof entry === "object") {
          history.push({ kind: "sale_change", ...(entry as Entry) });
        }
      }
    }
    for (const operation of operations) {
      const response = (operation.response ?? {}) as Record<string, unknown>;
      const correction = (response.correction ?? {}) as Record<string, unknown>;
      history.push({
        kind: "authoritative_operation",
        at: operation.createdAt.toISOString(),
        action: String(operation.operationType).replace("sale.correction.", ""),
        reason: correction.reason ?? null,
        performedByUserId: correction.performedByUserId ?? null,
        impact: response.impact ?? null,
      });
    }
    history.sort((a, b) => String(a.at ?? "").localeCompare(String(b.at ?? "")));

    return {
      sale: {
        id: sale.id,
        status: sale.status ?? null,
        total: toNumber(sale.total),
        balance: toNumber(sale.balance),
        version: sale.version,
      },
      history,
    } as unknown as Prisma.JsonObject;
  }
}

async function runCorrection(
  tx: Tx,
  input: SaleCorrectionInput,
  audit: { performedByUserId: string; reason: string; persistAudit: boolean },
): Promise<Record<string, unknown>> {
  const sale = await loadSale(tx, input.companyId, input.saleId);
  const activePayments = sale.payments.length;
  const installmentsBefore = await loadActiveInstallments(tx, sale.id);
  const before = {
    status: sale.status ?? null,
    total: toNumber(sale.total),
    balance: toNumber(sale.balance),
    initialPaid: toNumber(sale.initialPaid),
    initialPending: toNumber(sale.initialPendingAmount),
    financed: toNumber(sale.financedBalance),
    installmentCount: installmentsBefore.length,
    lotId: sale.lotId,
    clientId: sale.clientId,
    activePayments,
  };

  const now = new Date();
  const auditEntry = (extra: Record<string, unknown>) => ({
    action: input.action,
    performedByUserId: audit.performedByUserId,
    reason: audit.reason,
    performedAt: now.toISOString(),
    ...extra,
  });
  let detail: Record<string, unknown> = {};

  switch (input.action) {
    case "update_financing": {
      if (activePayments > 0) {
        throw new AuthoritativeError(
          "SALE_HAS_ACTIVE_PAYMENTS",
          "La venta tiene pagos activos: anula los pagos antes de cambiar importes, plazo o tasa.",
          409,
        );
      }
      const totalPrice = roundCurrency(
        input.totalPrice == null ? toNumber(sale.total) : Number(input.totalPrice),
      );
      const initialPaid = roundCurrency(
        input.initialPaidAmount == null
          ? toNumber(sale.initialPaid)
          : Number(input.initialPaidAmount),
      );
      const initialRequired = roundCurrency(
        input.initialRequiredAmount == null
          ? Math.max(toNumber(sale.initialRequiredAmount), initialPaid)
          : Number(input.initialRequiredAmount),
      );
      const financed = roundCurrency(
        calculateFinancedBalance({ salePrice: totalPrice, downPaymentAmount: initialPaid }),
      );
      const installmentCount =
        input.installmentCount == null
          ? (sale.installmentCount ?? installmentsBefore.length)
          : Number(input.installmentCount);
      const rate =
        input.monthlyInterestRate == null
          ? toNumber(sale.monthlyInterestRate)
          : Number(input.monthlyInterestRate);
      const validation = validateFinancing({
        totalPrice,
        initialPaidAmount: initialPaid,
        initialRequiredAmount: initialRequired,
        installmentCount,
        monthlyInterestRate: rate,
      });
      if (validation) {
        throw new AuthoritativeError(validation.code, validation.message, 400);
      }
      const saleDate = input.saleDate
        ? parseDate(input.saleDate, sale.saleDate ?? now)
        : (sale.saleDate ?? now);
      const initialPending = calculatePendingInitialPayment({
        requiredInitialPayment: initialRequired,
        initialPaymentPaid: initialPaid,
      });
      const status = saleStatusFor({
        initialRequiredAmount: initialRequired,
        initialPaidAmount: initialPaid,
        financedBalance: financed,
      });

      // El cronograma abierto se reemplaza conservando la historia (soft delete).
      for (const row of installmentsBefore) {
        await tx.installment.update({
          where: { id: row.id },
          data: {
            deletedAt: now,
            raw: audit.persistAudit
              ? (appendSaleAudit(row.raw, {
                  ...auditEntry({ role: "replaced_by_financing" }),
                }) as unknown as Prisma.InputJsonValue)
              : (row.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
      }
      let createdCount = 0;
      if (financed > 0.009 && installmentCount > 0) {
        const dueDates = canonicalInstallmentDueDates(saleDate, installmentCount);
        const schedule = buildInstallmentSchedule({
          saleDate,
          dueDates,
          financedBalance: financed,
          monthlyInterest: rate,
          installmentCount,
          statusAsOf: now,
        });
        for (const planned of schedule) {
          await tx.installment.create({
            data: {
              companyId: sale.companyId,
              syncId: newSyncId("installment"),
              saleId: sale.id,
              saleSyncId: sale.syncId,
              installmentNumber: planned.installmentNumber,
              dueDate: planned.dueDate,
              openingBalance: decimal(planned.openingBalance),
              principalAmount: decimal(planned.principalAmount),
              interestAmount: decimal(planned.interestAmount),
              totalAmount: decimal(planned.totalAmount),
              paidAmount: decimal(0),
              paidPrincipalAmount: decimal(0),
              paidInterestAmount: decimal(0),
              endingBalance: decimal(planned.endingBalance),
              status: "pendiente",
            },
          });
          createdCount += 1;
        }
      }
      await tx.sale.update({
        where: { id: sale.id },
        data: {
          saleDate,
          total: decimal(totalPrice),
          initialRequiredAmount: decimal(initialRequired),
          initialPaid: decimal(initialPaid),
          initialPendingAmount: decimal(initialPending),
          financedBalance: decimal(financed),
          balance: decimal(financed),
          installmentCount,
          monthlyInterestRate: decimal(rate),
          status,
          activationDate: initialPending <= 0.009 ? saleDate : null,
          initialPaymentDeadline: input.initialPaymentDeadline
            ? parseDate(input.initialPaymentDeadline, sale.initialPaymentDeadline ?? now)
            : sale.initialPaymentDeadline,
          raw: audit.persistAudit
            ? (appendSaleAudit(sale.raw, {
                ...auditEntry({
                  role: "financing",
                  before: {
                    total: before.total,
                    initialPaid: before.initialPaid,
                    financed: before.financed,
                    installmentCount: before.installmentCount,
                  },
                  after: {
                    total: totalPrice,
                    initialPaid,
                    financed,
                    installmentCount,
                  },
                }),
              }) as unknown as Prisma.InputJsonValue)
            : sale.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      if (sale.lotId) {
        await tx.lot.update({
          where: { id: sale.lotId },
          data: {
            status:
              status === "activa" || status === "pagada" ? "vendido" : "reservado",
            version: { increment: 1 },
          },
        });
      }
      detail = {
        totalPrice,
        initialPaid,
        initialRequired,
        initialPending,
        financed,
        installmentCount,
        monthlyInterestRate: rate,
        createdInstallments: createdCount,
        status,
      };
      break;
    }

    case "change_client": {
      const clientId = String(input.clientId ?? "").trim();
      if (!clientId) {
        throw new AuthoritativeError(
          "CLIENT_REQUIRED",
          "Selecciona el cliente.",
          400,
        );
      }
      const client = await tx.client.findFirst({
        where: { id: clientId, companyId: sale.companyId, deletedAt: null },
        select: { id: true, syncId: true, name: true },
      });
      if (!client) {
        throw new AuthoritativeError(
          "CLIENT_NOT_FOUND",
          "El cliente seleccionado no existe en la empresa.",
          404,
        );
      }
      if (activePayments > 0) {
        throw new AuthoritativeError(
          "SALE_HAS_ACTIVE_PAYMENTS",
          "La venta tiene pagos activos: no se puede cambiar el cliente sin anular esos pagos.",
          409,
        );
      }
      await tx.sale.update({
        where: { id: sale.id },
        data: {
          clientId: client.id,
          clientSyncId: client.syncId,
          raw: audit.persistAudit
            ? (appendSaleAudit(sale.raw, {
                ...auditEntry({
                  role: "client_change",
                  previousClientId: before.clientId,
                  newClientId: client.id,
                }),
              }) as unknown as Prisma.InputJsonValue)
            : sale.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      await tx.payment.updateMany({
        where: { saleId: sale.id, deletedAt: null },
        data: { clientId: client.id, clientSyncId: client.syncId },
      });
      detail = {
        previousClientId: before.clientId,
        newClientId: client.id,
        newClientName: client.name,
      };
      break;
    }

    case "change_lot": {
      const lotId = String(input.lotId ?? "").trim();
      if (!lotId) {
        throw new AuthoritativeError("LOT_REQUIRED", "Selecciona el solar.", 400);
      }
      const lot = await tx.lot.findFirst({
        where: { id: lotId, companyId: sale.companyId, deletedAt: null },
        select: { id: true, syncId: true, block: true, number: true },
      });
      if (!lot) {
        throw new AuthoritativeError(
          "LOT_NOT_FOUND",
          "El solar seleccionado no existe en la empresa.",
          404,
        );
      }
      await assertLotFree(tx, sale.companyId, lot.id, sale.id);
      const soldStatus =
        sale.status === "activa" || sale.status === "pagada"
          ? "vendido"
          : "reservado";
      if (sale.lotId && sale.lotId !== lot.id) {
        await tx.lot.update({
          where: { id: sale.lotId },
          data: { status: "disponible", version: { increment: 1 } },
        });
      }
      await tx.sale.update({
        where: { id: sale.id },
        data: {
          lotId: lot.id,
          lotSyncId: lot.syncId,
          raw: audit.persistAudit
            ? (appendSaleAudit(sale.raw, {
                ...auditEntry({
                  role: "lot_change",
                  previousLotId: before.lotId,
                  newLotId: lot.id,
                }),
              }) as unknown as Prisma.InputJsonValue)
            : sale.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      await tx.lot.update({
        where: { id: lot.id },
        data: { status: soldStatus, version: { increment: 1 } },
      });
      detail = {
        previousLotId: before.lotId,
        newLotId: lot.id,
        lotLabel: `${lot.block ?? ""}${lot.number ?? ""}`.trim(),
        lotStatus: soldStatus,
      };
      break;
    }

    case "cancel": {
      if (sale.status === "cancelada") {
        throw new AuthoritativeError(
          "SALE_ALREADY_CANCELLED",
          "La venta ya esta cancelada.",
          409,
        );
      }
      const snapshot = {
        statusBefore: sale.status ?? null,
        balanceBefore: toNumber(sale.balance),
        initialPaidBefore: toNumber(sale.initialPaid),
        initialPendingBefore: toNumber(sale.initialPendingAmount),
        financedBefore: toNumber(sale.financedBalance),
        lotIdBefore: sale.lotId,
        installmentStates: installmentsBefore.map((row) => ({
          id: row.id,
          status: row.status ?? null,
          dueDate: row.dueDate?.toISOString() ?? null,
          paidAmount: toNumber(row.paidAmount),
        })),
      };
      await cancelSaleInTransaction(tx, {
        companyId: sale.companyId,
        saleId: sale.id,
        cancelledByUserId: audit.performedByUserId,
        idempotencyKey: `correction-cancel-${sale.id}-${now.getTime()}`,
        reason: audit.reason,
        cancelledAt: now,
      });
      if (audit.persistAudit) {
        const refreshed = await tx.sale.findUnique({
          where: { id: sale.id },
          select: { raw: true },
        });
        const merged = appendSaleAudit(
          refreshed?.raw,
          auditEntry({ role: "cancel" }),
        );
        // El snapshot se guarda en la RAIZ de `raw` para que `restore` lo lea
        // sin depender del historial de correcciones.
        merged.cancellationSnapshot = snapshot;
        await tx.sale.update({
          where: { id: sale.id },
          data: { raw: merged as unknown as Prisma.InputJsonValue },
        });
      }
      detail = { cancelledAt: now.toISOString(), snapshot };
      break;
    }

    case "restore": {
      const raw = (sale.raw ?? {}) as Record<string, unknown>;
      const snapshot = raw.cancellationSnapshot as Record<string, unknown> | undefined;
      if (sale.status !== "cancelada" || sale.deletedAt === null) {
        throw new AuthoritativeError(
          "SALE_NOT_CANCELLED",
          "Solo se puede restaurar una venta cancelada.",
          409,
        );
      }
      if (!snapshot) {
        throw new AuthoritativeError(
          "RESTORE_SNAPSHOT_MISSING",
          "Esta venta se cancelo antes de existir el motor de restauracion: no hay estado financiero seguro que restaurar. Crea una venta nueva.",
          409,
        );
      }
      const lotIdBefore = snapshot.lotIdBefore
        ? String(snapshot.lotIdBefore)
        : null;
      if (lotIdBefore) {
        await assertLotFree(tx, sale.companyId, lotIdBefore, sale.id);
      }
      const statusBefore = String(snapshot.statusBefore ?? "activa");
      const balanceBefore = roundCurrency(Number(snapshot.balanceBefore ?? 0));
      const installmentStates = Array.isArray(snapshot.installmentStates)
        ? (snapshot.installmentStates as Array<Record<string, unknown>>)
        : [];

      await tx.sale.update({
        where: { id: sale.id },
        data: {
          status: statusBefore,
          deletedAt: null,
          balance: decimal(balanceBefore),
          initialPaid: decimal(Number(snapshot.initialPaidBefore ?? 0)),
          initialPendingAmount: decimal(
            Number(snapshot.initialPendingBefore ?? 0),
          ),
          financedBalance: decimal(Number(snapshot.financedBefore ?? 0)),
          raw: audit.persistAudit
            ? (appendSaleAudit(sale.raw, {
                ...auditEntry({ role: "restore", statusBefore }),
              }) as unknown as Prisma.InputJsonValue)
            : sale.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      for (const state of installmentStates) {
        const id = String(state.id ?? "");
        if (!id) continue;
        const dueDate = state.dueDate
          ? new Date(String(state.dueDate))
          : null;
        const paidAmount = Number(state.paidAmount ?? 0);
        await tx.installment.update({
          where: { id },
          data: {
            deletedAt: null,
            status: String(state.status ?? "pendiente"),
            ...(dueDate ? { dueDate } : {}),
            ...(paidAmount > 0.009 ? {} : {}),
            version: { increment: 1 },
          },
        });
      }
      if (lotIdBefore) {
        await tx.lot.update({
          where: { id: lotIdBefore },
          data: {
            status:
              statusBefore === "activa" || statusBefore === "pagada"
                ? "vendido"
                : "reservado",
            version: { increment: 1 },
          },
        });
      }
      detail = {
        restoredStatus: statusBefore,
        restoredBalance: balanceBefore,
        restoredInstallments: installmentStates.length,
      };
      break;
    }

    default:
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de venta no soportada.",
        400,
      );
  }

  const afterInstallments = await loadActiveInstallments(tx, sale.id);
  const refreshed = await tx.sale.findUnique({
    where: { id: sale.id },
    select: {
      status: true,
      total: true,
      balance: true,
      version: true,
      initialPaid: true,
      financedBalance: true,
    },
  });
  const after = {
    status: refreshed?.status ?? null,
    total: toNumber(refreshed?.total),
    balance: toNumber(refreshed?.balance),
    installmentCount: afterInstallments.length,
  };

  return {
    saleId: sale.id,
    saleVersion: sale.version,
    action: input.action,
    detail,
    impact: {
      statusBefore: before.status,
      statusAfter: after.status,
      totalBefore: before.total,
      totalAfter: after.total,
      balanceBefore: before.balance,
      balanceAfter: after.balance,
      initialPaidBefore: before.initialPaid,
      initialPaidAfter: toNumber(refreshed?.initialPaid),
      financedBefore: before.financed,
      financedAfter: toNumber(refreshed?.financedBalance),
      installmentCountBefore: before.installmentCount,
      installmentCountAfter: after.installmentCount,
      activePayments: before.activePayments,
      lotChanged:
        (detail.previousLotId ?? before.lotId) !== (detail.newLotId ?? before.lotId),
      clientChanged:
        (detail.previousClientId ?? before.clientId) !==
        (detail.newClientId ?? before.clientId),
    },
  };
}
