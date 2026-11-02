import { Prisma, PrismaClient } from "@prisma/client";
import { AuthoritativeError } from "./authoritativeErrors.service";
import {
  addMonths,
  buildInstallmentSchedule,
  roundCurrency,
  resolveInstallmentStatus,
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
  resolveSaleLateFeeState,
} from "./authoritativePayment.service";

/**
 * FASE 02 — Gestion administrativa de CUOTAS por el OWNER.
 *
 * REGLAS FINANCIERAS (invariantes que este motor garantiza y valida):
 *
 *  I1. `Sale.balance` == suma del capital pendiente de las cuotas activas.
 *  I2. Una cuota con pagos aplicados (`paidAmount > 0`) NUNCA se edita ni se
 *      elimina: su historia financiera es evidencia y los pagos no se tocan.
 *  I3. El capital total del contrato no cambia por editar cuotas: mover capital
 *      siempre se compensa (traslado entre cuotas), nunca se crea ni se destruye.
 *  I4. Las fechas de vencimiento de las cuotas activas se mantienen ordenadas.
 *
 * Toda operacion es atomica (una transaccion), idempotente (operationKey),
 * bloquea la venta (`SELECT ... FOR UPDATE`), valida version optimista opcional
 * y deja auditoria en `Installment.raw.corrections` + `AuthoritativeOperation`.
 */

export type InstallmentCorrectionAction =
  | "change_due_date"
  | "change_amounts"
  | "add_installment"
  | "remove_installment"
  | "reschedule";

const ACTIONS: readonly InstallmentCorrectionAction[] = [
  "change_due_date",
  "change_amounts",
  "add_installment",
  "remove_installment",
  "reschedule",
];

export function isInstallmentCorrectionAction(
  value: unknown,
): value is InstallmentCorrectionAction {
  return (
    typeof value === "string" &&
    (ACTIONS as readonly string[]).includes(value)
  );
}

export type InstallmentCorrectionInput = {
  companyId: string;
  saleId: string;
  action: InstallmentCorrectionAction;
  installmentId?: string | null;
  dueDate?: string | Date | null;
  principalAmount?: number | null;
  interestAmount?: number | null;
  installmentCount?: number | null;
  firstDueDate?: string | Date | null;
};

export type ApplyInstallmentCorrectionInput = InstallmentCorrectionInput & {
  performedByUserId: string;
  reason: string;
  idempotencyKey: string;
  expectedSaleVersion?: number | null;
};

/** Cuota apta para edicion: activa y sin pagos aplicados. */
export function isEditableInstallment(row: {
  deletedAt: Date | null;
  paidAmount: unknown;
}) {
  return row.deletedAt === null && toNumber(row.paidAmount) <= 0.009;
}

export function isClosedStatus(status: string | null | undefined) {
  return status === "pagada" || status === "ajustada" || status === "cancelada";
}

/** Valida que la nueva fecha respete el orden del cronograma. */
export function validateDueDateOrdering(input: {
  dueDate: Date;
  saleDate: Date | null;
  previousDueDate: Date | null;
  nextDueDate: Date | null;
}): { code: string; message: string } | null {
  if (Number.isNaN(input.dueDate.getTime())) {
    return {
      code: "INVALID_DUE_DATE",
      message: "La fecha de vencimiento no es valida.",
    };
  }
  if (input.saleDate && input.dueDate.getTime() < input.saleDate.getTime()) {
    return {
      code: "DUE_DATE_BEFORE_SALE",
      message: "La fecha de vencimiento no puede ser anterior a la fecha de la venta.",
    };
  }
  if (
    input.previousDueDate &&
    input.dueDate.getTime() <= input.previousDueDate.getTime()
  ) {
    return {
      code: "DUE_DATE_OUT_OF_ORDER",
      message:
        "La fecha debe ser posterior al vencimiento de la cuota anterior para mantener el orden del cronograma.",
    };
  }
  if (input.nextDueDate && input.dueDate.getTime() >= input.nextDueDate.getTime()) {
    return {
      code: "DUE_DATE_OUT_OF_ORDER",
      message:
        "La fecha debe ser anterior al vencimiento de la cuota siguiente para mantener el orden del cronograma.",
    };
  }
  return null;
}

/** Fechas mensuales para una reprogramacion, ancladas a `firstDueDate`. */
export function buildRescheduleDueDates(
  firstDueDate: Date,
  installmentCount: number,
): Date[] {
  const dates: Date[] = [];
  for (let index = 0; index < installmentCount; index += 1) {
    dates.push(addMonths(firstDueDate, index));
  }
  return dates;
}

type Tx = Prisma.TransactionClient;

type LoadedSale = Awaited<ReturnType<typeof loadSaleForCorrection>>;

async function loadSaleForCorrection(tx: Tx, companyId: string, saleId: string) {
  const sale = await tx.sale.findFirst({
    where: { id: saleId, companyId, deletedAt: null },
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

function principalOutstanding(
  rows: ReadonlyArray<{ principalAmount: unknown; paidPrincipalAmount: unknown }>,
) {
  return roundCurrency(
    rows.reduce(
      (sum, row) =>
        sum +
        Math.max(
          toNumber(row.principalAmount) - toNumber(row.paidPrincipalAmount),
          0,
        ),
      0,
    ),
  );
}

async function loadMoraState(tx: Tx, sale: LoadedSale) {
  const installments = await loadActiveInstallments(tx, sale.id);
  const state = await resolveSaleLateFeeState(
    tx,
    sale.companyId,
    sale,
    installments,
    new Date(),
  );
  return {
    grossLateFees: roundCurrency(state.grossTotal),
    outstandingLateFees: roundCurrency(state.outstandingTotal),
    waivedLateFees: roundCurrency(state.waivedTotal),
  };
}

async function nextDueDateOf(tx: Tx, saleId: string) {
  const row = await tx.installment.findFirst({
    where: {
      saleId,
      deletedAt: null,
      status: { notIn: ["pagada", "ajustada", "cancelada"] },
    },
    orderBy: { dueDate: "asc" },
    select: { dueDate: true },
  });
  return row?.dueDate ?? null;
}

/**
 * Recalcula la cadena opening/ending de las cuotas ABIERTAS (sin pagos) a partir
 * del capital pendiente real de la venta. No toca cuotas con pagos aplicados.
 */
async function recomputeOpenChain(tx: Tx, saleId: string, startingBalance: number) {
  const rows = await tx.installment.findMany({
    where: { saleId, deletedAt: null },
    orderBy: [{ installmentNumber: "asc" }, { dueDate: "asc" }],
  });
  let cursor = startingBalance;
  for (const row of rows) {
    const paid = toNumber(row.paidAmount);
    const principal = toNumber(row.principalAmount);
    if (paid > 0.009) {
      // Cuota con pagos: su capital pendiente ya esta descontado del saldo.
      cursor = roundCurrency(cursor - Math.max(toNumber(row.paidPrincipalAmount), 0));
      continue;
    }
    const opening = cursor;
    const ending = roundCurrency(opening - principal);
    cursor = ending;
    await tx.installment.update({
      where: { id: row.id },
      data: {
        openingBalance: decimal(opening),
        endingBalance: decimal(ending < 0 ? 0 : ending),
        version: { increment: 1 },
      },
    });
  }
}

function appendInstallmentAudit(
  raw: unknown,
  entry: Record<string, unknown>,
): Prisma.InputJsonValue {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  const previous = Array.isArray((base as Record<string, unknown>).corrections)
    ? ((base as Record<string, unknown>).corrections as unknown[])
    : [];
  base.corrections = [...previous, entry].slice(-20);
  return base as Prisma.InputJsonValue;
}

export class InstallmentCorrectionService {
  constructor(private readonly prisma: PrismaClient) {}

  /**
   * Previsualizacion EXACTA: ejecuta la misma logica dentro de una transaccion y
   * la revierte, devolviendo el impacto real (capital, proximo vencimiento y
   * mora) sin escribir nada.
   */
  async previewInstallmentCorrection(
    input: InstallmentCorrectionInput,
  ): Promise<Prisma.JsonObject> {
    if (!isInstallmentCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de cuota no soportada.",
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
        return {
          ...error.result,
          preview: true,
        } as unknown as Prisma.JsonObject;
      }
      throw error;
    }
    throw new AuthoritativeError(
      "PREVIEW_FAILED",
      "No se pudo calcular la previsualizacion.",
      500,
    );
  }

  async applyInstallmentCorrection(
    input: ApplyInstallmentCorrectionInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    if (!isInstallmentCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de cuota no soportada.",
        400,
      );
    }
    const reason = String(input.reason ?? "").trim();
    if (!reason) {
      throw new AuthoritativeError(
        "CORRECTION_REASON_REQUIRED",
        "Indica el motivo de la correccion del cronograma.",
        400,
      );
    }
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: `installment.correction.${input.action}`,
        requestPayload: {
          saleId: input.saleId,
          action: input.action,
          installmentId: input.installmentId ?? null,
          dueDate: input.dueDate ?? null,
          principalAmount: input.principalAmount ?? null,
          interestAmount: input.interestAmount ?? null,
          installmentCount: input.installmentCount ?? null,
          firstDueDate: input.firstDueDate ?? null,
          reason,
          performedByUserId: input.performedByUserId,
        },
        run: async () => {
          const sale = await loadSaleForCorrection(
            tx,
            input.companyId,
            input.saleId,
          );
          await lockSaleForFinancialMutation(tx, sale.id);
          const locked = await loadSaleForCorrection(
            tx,
            input.companyId,
            input.saleId,
          );
          if (
            input.expectedSaleVersion != null &&
            locked.version !== input.expectedSaleVersion
          ) {
            throw new AuthoritativeError(
              "SALE_VERSION_CONFLICT",
              "El cronograma cambio desde que abriste el dialogo. Recarga la venta e intentalo de nuevo.",
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
            resourceId: sale.id,
          };
        },
      }),
    );
  }

  /** Auditoria de solo lectura de las correcciones de cronograma de una venta. */
  async getInstallmentCorrectionHistory(input: {
    companyId: string;
    saleId: string;
  }): Promise<Prisma.JsonObject> {
    const sale = await loadSaleForCorrection(
      this.prisma as unknown as Tx,
      input.companyId,
      input.saleId,
    );
    const installments = await this.prisma.installment.findMany({
      where: { companyId: input.companyId, saleId: sale.id },
      orderBy: [{ installmentNumber: "asc" }, { dueDate: "asc" }],
      select: {
        id: true,
        installmentNumber: true,
        dueDate: true,
        totalAmount: true,
        paidAmount: true,
        status: true,
        deletedAt: true,
        raw: true,
      },
    });
    const operations = await this.prisma.authoritativeOperation.findMany({
      where: {
        companyId: input.companyId,
        resourceId: sale.id,
        operationType: { startsWith: "installment.correction." },
      },
      select: { operationType: true, createdAt: true, response: true },
      orderBy: { createdAt: "asc" },
    });

    type Entry = Record<string, unknown>;
    const history: Entry[] = [];
    for (const installment of installments) {
      const raw = (installment.raw ?? {}) as Record<string, unknown>;
      if (!Array.isArray(raw.corrections)) continue;
      for (const entry of raw.corrections as unknown[]) {
        if (!entry || typeof entry !== "object") continue;
        history.push({
          kind: "installment_change",
          installmentNumber: installment.installmentNumber,
          ...(entry as Entry),
        });
      }
    }
    for (const operation of operations) {
      const response = (operation.response ?? {}) as Record<string, unknown>;
      const correction = (response.correction ?? {}) as Record<string, unknown>;
      history.push({
        kind: "authoritative_operation",
        at: operation.createdAt.toISOString(),
        action: String(operation.operationType).replace(
          "installment.correction.",
          "",
        ),
        reason: correction.reason ?? null,
        performedByUserId: correction.performedByUserId ?? null,
        impact: response.impact ?? null,
      });
    }
    history.sort((a, b) =>
      String(a.at ?? "").localeCompare(String(b.at ?? "")),
    );

    return {
      sale: {
        id: sale.id,
        status: sale.status ?? null,
        balance: toNumber(sale.balance),
        version: sale.version,
      },
      installments: installments.map((row) => ({
        id: row.id,
        installmentNumber: row.installmentNumber,
        dueDate: row.dueDate?.toISOString() ?? null,
        totalAmount: toNumber(row.totalAmount),
        paidAmount: toNumber(row.paidAmount),
        status: row.status,
        removed: row.deletedAt !== null,
      })),
      history,
    } as unknown as Prisma.JsonObject;
  }
}

async function runCorrection(
  tx: Tx,
  input: InstallmentCorrectionInput,
  audit: {
    performedByUserId: string;
    reason: string;
    persistAudit: boolean;
  },
): Promise<Record<string, unknown>> {
  const sale = await loadSaleForCorrection(tx, input.companyId, input.saleId);
  const beforeInstallments = await loadActiveInstallments(tx, sale.id);
  const before = {
    outstandingPrincipal: principalOutstanding(beforeInstallments),
    nextDueDate: await nextDueDateOf(tx, sale.id),
    ...(await loadMoraState(tx, sale)),
    installmentCount: beforeInstallments.length,
  };

  const now = new Date();
  const auditEntry = (extra: Record<string, unknown>) => ({
    action: input.action,
    performedByUserId: audit.performedByUserId,
    reason: audit.reason,
    performedAt: now.toISOString(),
    ...extra,
  });
  const touched: string[] = [];
  let detail: Record<string, unknown> = {};

  const activeRows = [...beforeInstallments].sort(
    (a, b) => (a.installmentNumber ?? 0) - (b.installmentNumber ?? 0),
  );

  switch (input.action) {
    case "change_due_date": {
      const target = requireInstallment(activeRows, input.installmentId);
      if (!isEditableInstallment(target)) {
        throw new AuthoritativeError(
          "INSTALLMENT_HAS_PAYMENTS",
          "Esta cuota ya tiene pagos aplicados: su fecha es evidencia historica y no se puede mover.",
          409,
        );
      }
      const newDueDate = parseDate(input.dueDate, undefined as unknown as Date);
      const index = activeRows.findIndex((row) => row.id === target.id);
      const ordering = validateDueDateOrdering({
        dueDate: newDueDate,
        saleDate: sale.saleDate,
        previousDueDate: index > 0 ? activeRows[index - 1].dueDate : null,
        nextDueDate:
          index < activeRows.length - 1 ? activeRows[index + 1].dueDate : null,
      });
      if (ordering) {
        throw new AuthoritativeError(ordering.code, ordering.message, 409);
      }
      await tx.installment.update({
        where: { id: target.id },
        data: {
          dueDate: newDueDate,
          status: resolveInstallmentStatus({
            dueDate: newDueDate,
            paidAmount: 0,
            totalAmount: toNumber(target.totalAmount),
            asOf: now,
          }),
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                target.raw,
                auditEntry({
                  previousDueDate: target.dueDate?.toISOString() ?? null,
                  newDueDate: newDueDate.toISOString(),
                }),
              )
            : target.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      touched.push(target.id);
      detail = {
        installmentNumber: target.installmentNumber,
        previousDueDate: target.dueDate?.toISOString() ?? null,
        newDueDate: newDueDate.toISOString(),
      };
      break;
    }

    case "change_amounts": {
      const target = requireInstallment(activeRows, input.installmentId);
      if (!isEditableInstallment(target)) {
        throw new AuthoritativeError(
          "INSTALLMENT_HAS_PAYMENTS",
          "Esta cuota ya tiene pagos aplicados: sus montos son evidencia historica y no se pueden cambiar.",
          409,
        );
      }
      const newPrincipal =
        input.principalAmount == null
          ? toNumber(target.principalAmount)
          : roundCurrency(Number(input.principalAmount));
      const newInterest =
        input.interestAmount == null
          ? toNumber(target.interestAmount)
          : roundCurrency(Number(input.interestAmount));
      if (
        !Number.isFinite(newPrincipal) ||
        !Number.isFinite(newInterest) ||
        newPrincipal < 0 ||
        newInterest < 0 ||
        newPrincipal + newInterest <= 0
      ) {
        throw new AuthoritativeError(
          "INVALID_INSTALLMENT_AMOUNT",
          "El capital y el interes deben ser cero o positivos y el total mayor que cero.",
          400,
        );
      }
      const delta = roundCurrency(newPrincipal - toNumber(target.principalAmount));
      const compensation = delta === 0 ? null : lastOpenOther(activeRows, target.id);
      if (delta !== 0 && !compensation) {
        throw new AuthoritativeError(
          "RESCHEDULE_REQUIRED",
          "Para cambiar el capital de la ultima cuota abierta usa 'Reprogramar cuotas': el capital total del contrato no puede cambiar.",
          409,
        );
      }
      if (compensation && toNumber(compensation.paidAmount) > 0.009) {
        throw new AuthoritativeError(
          "COMPENSATION_INSTALLMENT_HAS_PAYMENTS",
          "La cuota que debe absorber la diferencia tiene pagos: reprograma el cronograma en su lugar.",
          409,
        );
      }
      await tx.installment.update({
        where: { id: target.id },
        data: {
          principalAmount: decimal(newPrincipal),
          interestAmount: decimal(newInterest),
          totalAmount: decimal(roundCurrency(newPrincipal + newInterest)),
          status: resolveInstallmentStatus({
            dueDate: target.dueDate ?? now,
            paidAmount: 0,
            totalAmount: roundCurrency(newPrincipal + newInterest),
            asOf: now,
          }),
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                target.raw,
                auditEntry({
                  previousPrincipal: toNumber(target.principalAmount),
                  previousInterest: toNumber(target.interestAmount),
                  newPrincipal,
                  newInterest,
                  compensatedInstallmentNumber:
                    compensation?.installmentNumber ?? null,
                }),
              )
            : target.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      touched.push(target.id);
      if (compensation && delta !== 0) {
        const compensatedPrincipal = roundCurrency(
          toNumber(compensation.principalAmount) - delta,
        );
        if (compensatedPrincipal < 0) {
          throw new AuthoritativeError(
            "COMPENSATION_IMPOSSIBLE",
            "La diferencia no cabe en la cuota compensatoria: el cronograma quedaria inconsistente.",
            409,
          );
        }
        const compensatedTotal = roundCurrency(
          compensatedPrincipal + toNumber(compensation.interestAmount),
        );
        await tx.installment.update({
          where: { id: compensation.id },
          data: {
            principalAmount: decimal(compensatedPrincipal),
            totalAmount: decimal(compensatedTotal),
            status: resolveInstallmentStatus({
              dueDate: compensation.dueDate ?? now,
              paidAmount: 0,
              totalAmount: compensatedTotal,
              asOf: now,
            }),
            raw: audit.persistAudit
              ? appendInstallmentAudit(
                  compensation.raw,
                  auditEntry({
                    role: "compensation",
                    forInstallmentNumber: target.installmentNumber,
                    previousPrincipal: toNumber(compensation.principalAmount),
                    newPrincipal: compensatedPrincipal,
                  }),
                )
              : compensation.raw ?? Prisma.JsonNull,
            version: { increment: 1 },
          },
        });
        touched.push(compensation.id);
      }
      detail = {
        installmentNumber: target.installmentNumber,
        newPrincipal,
        newInterest,
        newTotal: roundCurrency(newPrincipal + newInterest),
        compensatedInstallmentNumber: compensation?.installmentNumber ?? null,
      };
      break;
    }

    case "add_installment": {
      const openRows = activeRows.filter((row) => !isClosedStatus(row.status));
      const last = openRows[openRows.length - 1];
      if (!last) {
        throw new AuthoritativeError(
          "NO_OPEN_INSTALLMENT",
          "La venta no tiene cuotas abiertas a las que agregar una nueva.",
          409,
        );
      }
      const lastPrincipal = toNumber(last.principalAmount);
      const requested =
        input.principalAmount == null
          ? roundCurrency(lastPrincipal / 2)
          : roundCurrency(Number(input.principalAmount));
      if (
        !Number.isFinite(requested) ||
        requested <= 0 ||
        requested >= lastPrincipal
      ) {
        throw new AuthoritativeError(
          "INVALID_SPLIT_AMOUNT",
          `El capital de la nueva cuota debe ser mayor que 0 y menor que el de la ultima cuota (${lastPrincipal.toFixed(2)}).`,
          409,
        );
      }
      const newDueDate = input.dueDate
        ? parseDate(input.dueDate, addMonths(last.dueDate ?? now, 1))
        : addMonths(last.dueDate ?? now, 1);
      if (last.dueDate && newDueDate.getTime() <= last.dueDate.getTime()) {
        throw new AuthoritativeError(
          "DUE_DATE_OUT_OF_ORDER",
          "La nueva cuota debe vencer despues de la ultima cuota existente.",
          409,
        );
      }
      const remainingLast = roundCurrency(lastPrincipal - requested);
      const remainingTotal = roundCurrency(
        remainingLast + toNumber(last.interestAmount),
      );
      await tx.installment.update({
        where: { id: last.id },
        data: {
          principalAmount: decimal(remainingLast),
          totalAmount: decimal(remainingTotal),
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                last.raw,
                auditEntry({
                  role: "split_source",
                  previousPrincipal: lastPrincipal,
                  newPrincipal: remainingLast,
                }),
              )
            : last.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      const nextNumber =
        activeRows.reduce(
          (max, row) => Math.max(max, row.installmentNumber ?? 0),
          0,
        ) + 1;
      const created = await tx.installment.create({
        data: {
          companyId: sale.companyId,
          syncId: newSyncId("installment"),
          saleId: sale.id,
          saleSyncId: sale.syncId,
          installmentNumber: nextNumber,
          dueDate: newDueDate,
          openingBalance: decimal(remainingLast),
          principalAmount: decimal(requested),
          interestAmount: decimal(0),
          totalAmount: decimal(requested),
          paidAmount: decimal(0),
          paidPrincipalAmount: decimal(0),
          paidInterestAmount: decimal(0),
          endingBalance: decimal(0),
          status: "pendiente",
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                null,
                auditEntry({ role: "created", splitFromInstallmentNumber: last.installmentNumber }),
              )
            : undefined,
        },
        select: { id: true, installmentNumber: true },
      });
      touched.push(last.id, created.id);
      detail = {
        createdInstallmentId: created.id,
        createdInstallmentNumber: created.installmentNumber,
        dueDate: newDueDate.toISOString(),
        principalAmount: requested,
      };
      break;
    }

    case "remove_installment": {
      const target = requireInstallment(activeRows, input.installmentId);
      if (!isEditableInstallment(target)) {
        throw new AuthoritativeError(
          "INSTALLMENT_HAS_PAYMENTS",
          "Esta cuota tiene pagos aplicados: no se puede eliminar sin alterar la historia financiera.",
          409,
        );
      }
      const openOthers = activeRows.filter(
        (row) => row.id !== target.id && !isClosedStatus(row.status),
      );
      const openTotal = activeRows.filter((row) => !isClosedStatus(row.status));
      if (openTotal.length <= 1) {
        throw new AuthoritativeError(
          "ONLY_INSTALLMENT_CANNOT_BE_REMOVED",
          "Es la unica cuota abierta: usa 'Reprogramar cuotas' para cambiar el plan.",
          409,
        );
      }
      const index = activeRows.findIndex((row) => row.id === target.id);
      const receiver =
        openOthers.find((row) => (row.installmentNumber ?? 0) > (target.installmentNumber ?? 0)) ??
        openOthers[openOthers.length - 1];
      if (!receiver) {
        throw new AuthoritativeError(
          "NO_RECEIVING_INSTALLMENT",
          "No hay una cuota abierta que pueda absorber el capital de esta cuota.",
          409,
        );
      }
      if (toNumber(receiver.paidAmount) > 0.009) {
        throw new AuthoritativeError(
          "NO_RECEIVING_INSTALLMENT",
          "La cuota que absorbería el capital tiene pagos: reprograma el cronograma en su lugar.",
          409,
        );
      }
      const movedPrincipal = toNumber(target.principalAmount);
      const receiverPrincipal = roundCurrency(
        toNumber(receiver.principalAmount) + movedPrincipal,
      );
      const receiverTotal = roundCurrency(
        receiverPrincipal + toNumber(receiver.interestAmount),
      );
      await tx.installment.update({
        where: { id: target.id },
        data: {
          deletedAt: now,
          paidAmount: decimal(0),
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                target.raw,
                auditEntry({
                  role: "removed",
                  movedPrincipal,
                  movedToInstallmentNumber: receiver.installmentNumber,
                }),
              )
            : target.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      await tx.installment.update({
        where: { id: receiver.id },
        data: {
          principalAmount: decimal(receiverPrincipal),
          totalAmount: decimal(receiverTotal),
          raw: audit.persistAudit
            ? appendInstallmentAudit(
                receiver.raw,
                auditEntry({
                  role: "absorption",
                  absorbedFromInstallmentNumber: target.installmentNumber,
                  previousPrincipal: toNumber(receiver.principalAmount),
                  newPrincipal: receiverPrincipal,
                }),
              )
            : receiver.raw ?? Prisma.JsonNull,
          version: { increment: 1 },
        },
      });
      touched.push(target.id, receiver.id);
      detail = {
        removedInstallmentId: target.id,
        removedInstallmentNumber: target.installmentNumber,
        movedPrincipal,
        movedToInstallmentNumber: receiver.installmentNumber,
        index,
      };
      break;
    }

    case "reschedule": {
      const count = Number(input.installmentCount ?? 0);
      if (!Number.isInteger(count) || count < 1 || count > 120) {
        throw new AuthoritativeError(
          "INVALID_INSTALLMENT_COUNT",
          "El numero de cuotas debe estar entre 1 y 120.",
          400,
        );
      }
      const openRows = activeRows.filter((row) => !isClosedStatus(row.status));
      if (openRows.length === 0) {
        throw new AuthoritativeError(
          "NO_OPEN_INSTALLMENT",
          "La venta no tiene cuotas abiertas que reprogramar.",
          409,
        );
      }
      const withPayments = openRows.filter((row) => toNumber(row.paidAmount) > 0.009);
      if (withPayments.length > 0) {
        throw new AuthoritativeError(
          "RESCHEDULE_BLOCKED_BY_PARTIAL_PAYMENTS",
          `Hay cuotas abiertas con pagos aplicados (${withPayments
            .map((row) => row.installmentNumber)
            .join(", ")}). Reprogramar solo las cuotas sin pagos o anula primero esos pagos.`,
          409,
        );
      }
      const totalPrincipal = principalOutstanding(openRows);
      if (totalPrincipal <= 0.009) {
        throw new AuthoritativeError(
          "NOTHING_TO_RESCHEDULE",
          "No hay capital pendiente en las cuotas abiertas.",
          409,
        );
      }
      const firstDueDate = input.firstDueDate
        ? parseDate(input.firstDueDate, addMonths(now, 1))
        : addMonths(now, 1);
      const dueDates = buildRescheduleDueDates(firstDueDate, count);
      const closedCount = activeRows.length - openRows.length;
      const schedule = buildInstallmentSchedule({
        saleDate: firstDueDate,
        dueDates,
        financedBalance: totalPrincipal,
        monthlyInterest: toNumber(sale.monthlyInterestRate),
        installmentCount: count,
        statusAsOf: now,
        startingInstallmentNumber: closedCount + 1,
      });
      if (schedule.length !== count) {
        throw new AuthoritativeError(
          "RESCHEDULE_FAILED",
          "No se pudo construir el nuevo cronograma con esos parametros.",
          409,
        );
      }
      // Las cuotas viejas SIN pagos se retiran conservando la historia.
      for (const row of openRows) {
        await tx.installment.update({
          where: { id: row.id },
          data: {
            deletedAt: now,
            raw: audit.persistAudit
              ? appendInstallmentAudit(
                  row.raw,
                  auditEntry({ role: "reschedule_removed" }),
                )
              : row.raw ?? Prisma.JsonNull,
            version: { increment: 1 },
          },
        });
        touched.push(row.id);
      }
      let number = closedCount + 1;
      for (const planned of schedule) {
        const created = await tx.installment.create({
          data: {
            companyId: sale.companyId,
            syncId: newSyncId("installment"),
            saleId: sale.id,
            saleSyncId: sale.syncId,
            installmentNumber: planned.installmentNumber ?? number,
            dueDate: planned.dueDate ?? dueDates[number - closedCount - 1],
            openingBalance: decimal(planned.openingBalance),
            principalAmount: decimal(planned.principalAmount),
            interestAmount: decimal(planned.interestAmount),
            totalAmount: decimal(planned.totalAmount),
            paidAmount: decimal(0),
            paidPrincipalAmount: decimal(0),
            paidInterestAmount: decimal(0),
            endingBalance: decimal(planned.endingBalance),
            status: "pendiente",
            raw: audit.persistAudit
              ? appendInstallmentAudit(
                  null,
                  auditEntry({ role: "reschedule_created", installmentNumber: number }),
                )
              : undefined,
          },
          select: { id: true },
        });
        touched.push(created.id);
        number += 1;
      }
      detail = {
        previousInstallmentCount: openRows.length,
        newInstallmentCount: count,
        firstDueDate: firstDueDate.toISOString(),
        totalPrincipal,
      };
      break;
    }

    default:
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion de cuota no soportada.",
        400,
      );
  }

  // ── Recalculo e invariantes ────────────────────────────────────────────────
  const afterInstallments = await loadActiveInstallments(tx, sale.id);
  const outstandingAfter = principalOutstanding(afterInstallments);

  await recomputeOpenChain(tx, sale.id, outstandingAfter);

  await tx.sale.update({
    where: { id: sale.id },
    data: {
      balance: decimal(outstandingAfter),
      version: { increment: 1 },
    },
  });

  const after = {
    outstandingPrincipal: outstandingAfter,
    nextDueDate: await nextDueDateOf(tx, sale.id),
    ...(await loadMoraState(tx, sale)),
    installmentCount: afterInstallments.length,
  };

  return {
    saleId: sale.id,
    saleVersion: sale.version,
    action: input.action,
    detail,
    touchedInstallmentIds: touched,
    impact: {
      outstandingPrincipalBefore: before.outstandingPrincipal,
      outstandingPrincipalAfter: after.outstandingPrincipal,
      nextDueDateBefore: before.nextDueDate?.toISOString() ?? null,
      nextDueDateAfter: after.nextDueDate?.toISOString() ?? null,
      installmentCountBefore: before.installmentCount,
      installmentCountAfter: after.installmentCount,
      grossLateFeesBefore: before.grossLateFees,
      grossLateFeesAfter: after.grossLateFees,
      outstandingLateFeesBefore: before.outstandingLateFees,
      outstandingLateFeesAfter: after.outstandingLateFees,
      waivedLateFeesBefore: before.waivedLateFees,
      waivedLateFeesAfter: after.waivedLateFees,
      // El capital del contrato no se crea ni se destruye con correcciones.
      principalPreserved:
        Math.abs(after.outstandingPrincipal - before.outstandingPrincipal) <= 0.011,
    },
  };
}

function requireInstallment<T extends { id: string }>(
  rows: ReadonlyArray<T>,
  installmentId: string | null | undefined,
): T {
  const id = String(installmentId ?? "").trim();
  if (!id) {
    throw new AuthoritativeError(
      "INSTALLMENT_REQUIRED",
      "Selecciona la cuota a corregir.",
      400,
    );
  }
  const row = rows.find((item) => item.id === id);
  if (!row) {
    throw new AuthoritativeError(
      "INSTALLMENT_NOT_FOUND",
      "La cuota seleccionada no existe en la venta.",
      404,
    );
  }
  return row;
}

function lastOpenOther<
  T extends { id: string; status: string | null },
>(rows: ReadonlyArray<T>, excludeId: string): T | null {
  const open = rows.filter(
    (row) => row.id !== excludeId && !isClosedStatus(row.status),
  );
  return open.length > 0 ? open[open.length - 1] : null;
}
