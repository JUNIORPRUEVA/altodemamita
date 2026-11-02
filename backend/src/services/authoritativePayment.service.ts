import { Prisma, PrismaClient } from "@prisma/client";
import { AuthoritativeError } from "./authoritativeErrors.service";
import {
  buildInstallmentSchedule,
  calculateEstimatedInstallmentAmount,
  calculateFinancedBalance,
  calculatePendingInitialPayment,
  resolveInstallmentStatus,
  resolveUpfrontSaleStatus,
  roundCurrency,
} from "./financing.service";
import {
  decimal,
  newSyncId,
  normalizePaymentMethod,
  parseDate,
  toNumber,
} from "./authoritativeSale.service";
import {
  IdempotentResult,
  requireIdempotencyKey,
  runIdempotentOperation,
} from "./idempotency.service";
import {
  BUSINESS_TIMEZONE,
  dateKeyInTimeZone,
  isPastDueBusinessDay,
} from "./installmentStatus.service";
import {
  LateFeeCalculationService,
  decimal as lateFeeDecimal,
} from "./lateFeeCalculation.service";
import { loadSaleLateFeeWaivers } from "./lateFeeWaiver.service";
import { readLateFeePolicy } from "./lateFeePolicy.service";
import {
  CorrectionAction,
  CorrectionDecision,
  CorrectionSnapshot,
  evaluatePaymentCorrection,
  isCorrectionAction,
} from "./paymentCorrection";

type TransactionClient = Prisma.TransactionClient;
type LoadedInstallment = Awaited<
  ReturnType<typeof loadActiveInstallments>
>[number];

/**
 * P0 IDENTIDAD FINANCIERA — metadata de correlacion.
 *
 * `Payment.syncId` identifica la FILA autoritativa (el servicio genera uno nuevo
 * por cada fila creada). `sourceSyncId` identifica la INTENCION del cliente que
 * la origino, porque una sola intencion offline puede producir N filas
 * autoritativas (una por aplicacion a cuota + una por capital).
 *
 * Se persiste dentro del JSON `raw` existente: no requiere migracion y no
 * reemplaza `Payment.syncId`.
 */
export function authoritativePaymentRaw(sourceSyncId?: string | null) {
  const normalized = sourceSyncId?.toString().trim();
  return {
    authoritativeSource: "phase_1d" as const,
    ...(normalized ? { sourceSyncId: normalized } : {}),
  };
}

export type RegisterAuthoritativePaymentInput = {
  companyId: string;
  receivedByUserId: string;
  idempotencyKey: string;
  saleId?: string;
  saleSyncId?: string;
  paymentDate?: string | Date;
  amountPaid?: number;
  amount?: number;
  paymentMethod?: string | null;
  paymentType?: string | null;
  paymentTypeOverride?: string | null;
  targetInstallmentId?: string | null;
  targetInstallmentNumber?: number | null;
  advanceInstallmentCount?: number | null;
  yearToPay?: number | null;
  reference?: string | null;
  quoteVersion?: string | null;
  /**
   * `sync_id` de la INTENCION offline original (correlacion, no identidad de
   * fila). Opcional: los pagos creados online directo no lo llevan.
   */
  sourceSyncId?: string | null;
};

export type AnnulAuthoritativePaymentInput = {
  companyId: string;
  annulledByUserId: string;
  idempotencyKey: string;
  paymentId: string;
  reason?: string | null;
  annulledAt?: string | Date;
  /**
   * Usuario administrador que autorizo la anulacion cuando el operador no
   * tenia permiso propio. `null`/ausente significa anulacion directa.
   */
  authorizedByUserId?: string | null;
};

export type SettlementQuoteInput = {
  companyId: string;
  saleId: string;
  asOfDate?: string | Date;
};

export type WaiveLateFeesInput = {
  companyId: string;
  saleId: string;
  operatorUserId: string;
  idempotencyKey: string;
  /** Confirmacion explicita del `Sale.syncId` a condonar. */
  confirmSaleSyncId: string;
  /** Corte ISO-8601: la mora acumulada hasta aqui queda condonada. */
  cutoffAt: string | Date;
  reason: string;
  /**
   * FASE 01D — monto PARCIAL a condonar.
   *
   * `null`/ausente = condonacion total de la mora exigible al corte. Si se
   * informa, el backend valida que no exceda la mora exigible y persiste ese
   * monto exacto; el motor distribuye la condonacion por cuota con el mismo
   * calculo autoritativo (nunca se acepta un importe sin tope).
   */
  waivedAmount?: number | null;
};

export type SettleSaleInput = {
  companyId: string;
  receivedByUserId: string;
  idempotencyKey: string;
  saleId: string;
  paymentDate?: string | Date;
  paymentMethod?: string | null;
  quoteVersion?: string | null;
  reference?: string | null;
};

export class AuthoritativePaymentService {
  constructor(private readonly prisma: PrismaClient) {}

  async getSettlementQuote(
    input: SettlementQuoteInput,
  ): Promise<Prisma.JsonObject> {
    return this.prisma.$transaction(async (tx) => {
      const sale = await loadSale(tx, {
        companyId: input.companyId,
        receivedByUserId: "",
        idempotencyKey: "quote",
        saleId: input.saleId,
      });
      const installments = await loadActiveInstallments(tx, sale.id);
      const asOfDate = parseDate(input.asOfDate, new Date());
      // Fase 2: la cotizacion usa EXACTAMENTE el mismo calculo de mora
      // exigible que la liquidacion real, para que el monto mostrado sea el
      // monto cobrado en el mismo corte.
      const lateFees = await resolveSettlementLateFees(
        tx,
        input.companyId,
        sale,
        installments,
        asOfDate,
      );
      return buildSettlementQuoteResponse(
        sale,
        installments,
        asOfDate,
        lateFees,
      );
    });
  }

  /**
   * Fase 2 (Windows) — Estado autoritativo de mora de una venta.
   *
   * Expone bruto / cobrado / condonado / exigible, total y por cuota, para que
   * los clientes muestren el monto REALMENTE COBRABLE en lugar de recalcularlo
   * localmente. Solo lectura y acotado a `companyId` (sin fuga entre empresas).
   */
  async getLateFeeSummary(
    input: SettlementQuoteInput,
  ): Promise<Prisma.JsonObject> {
    return this.prisma.$transaction(async (tx) => {
      const sale = await loadSale(tx, {
        companyId: input.companyId,
        receivedByUserId: "",
        idempotencyKey: "late-fee-summary",
        saleId: input.saleId,
      });
      const asOfDate = parseDate(input.asOfDate, new Date());
      const installments = await loadActiveInstallments(tx, sale.id);
      const state = await resolveSaleLateFeeState(
        tx,
        input.companyId,
        sale,
        installments,
        asOfDate,
      );
      return {
        saleId: sale.id,
        saleSyncId: sale.syncId,
        asOfDate: asOfDate.toISOString(),
        policyEnabled: state.policyEnabled,
        grossLateFees: state.grossTotal,
        collectedLateFees: state.collectedTotal,
        waivedLateFees: state.waivedTotal,
        outstandingLateFees: state.outstandingTotal,
        installments: state.installments,
      } as unknown as Prisma.JsonObject;
    });
  }

  /**
   * Condonacion PERSISTENTE de la mora exigible al corte indicado (OWNER).
   *
   * El monto NO se acepta del cliente: se recalcula aqui con el motor
   * autoritativo (`resolveSaleLateFeeState`) al instante de `cutoffAt`. La mora
   * posterior al corte sigue acumulandose. Idempotente por `idempotencyKey` y
   * blindado contra doble condonacion en el mismo corte.
   *
   * Toma el bloqueo financiero de la venta para no cruzarse con un pago o una
   * liquidacion simultaneos (ver `lockSaleForFinancialMutation`).
   */
  async waiveLateFees(
    input: WaiveLateFeesInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    const cutoff = parseDate(input.cutoffAt, undefined as unknown as Date);
    if (!cutoff || Number.isNaN(cutoff.getTime())) {
      throw new AuthoritativeError(
        "INVALID_CUTOFF",
        "cutoffAt debe ser una fecha ISO-8601 valida.",
        400,
      );
    }
    const reason = String(input.reason ?? "").trim();
    if (!reason) {
      throw new AuthoritativeError(
        "WAIVER_REASON_REQUIRED",
        "Indica el motivo de la condonacion.",
        400,
      );
    }
    // FASE 01D: monto parcial opcional. `null` = condonacion total.
    const requestedWaivedAmount =
      input.waivedAmount == null ? null : roundCurrency(Number(input.waivedAmount));
    if (
      requestedWaivedAmount !== null &&
      (!Number.isFinite(requestedWaivedAmount) || requestedWaivedAmount <= 0)
    ) {
      throw new AuthoritativeError(
        "INVALID_WAIVED_AMOUNT",
        "El monto a condonar debe ser mayor que cero.",
        400,
      );
    }
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: "admin.sale.waive_late_fees",
        requestPayload: {
          saleId: input.saleId,
          cutoffAt: cutoff.toISOString(),
          confirmSaleSyncId: input.confirmSaleSyncId,
          reason,
          waivedAmount: requestedWaivedAmount,
        },
        run: async () => {
          const sale = await loadSale(tx, {
            companyId: input.companyId,
            receivedByUserId: input.operatorUserId,
            idempotencyKey: operationKey,
            saleId: input.saleId,
          });
          if (sale.syncId !== input.confirmSaleSyncId) {
            throw new AuthoritativeError(
              "SALE_CONFIRMATION_MISMATCH",
              "La confirmacion (saleSyncId) no coincide con la venta.",
              409,
            );
          }
          await lockSaleForFinancialMutation(tx, sale.id);
          const duplicated = await tx.lateFeeWaiver.findFirst({
            where: {
              companyId: input.companyId,
              saleId: sale.id,
              cutoffAt: cutoff,
            },
            select: { id: true },
          });
          if (duplicated) {
            throw new AuthoritativeError(
              "LATE_FEE_ALREADY_WAIVED",
              `Ya existe una condonacion para esta venta con el mismo corte (${duplicated.id}).`,
              409,
            );
          }
          const installments = await loadActiveInstallments(tx, sale.id);
          const state = await resolveSaleLateFeeState(
            tx,
            input.companyId,
            sale,
            installments,
            cutoff,
          );
          if (state.outstandingTotal <= 0) {
            throw new AuthoritativeError(
              "NOTHING_TO_WAIVE",
              "La mora exigible al corte es 0.00; no hay nada que condonar.",
              409,
            );
          }
          if (
            requestedWaivedAmount !== null &&
            requestedWaivedAmount > roundCurrency(state.outstandingTotal) + 0.009
          ) {
            throw new AuthoritativeError(
              "WAIVED_AMOUNT_EXCEEDS_OUTSTANDING",
              `La condonacion (${requestedWaivedAmount.toFixed(2)}) excede la mora exigible al corte (${roundCurrency(state.outstandingTotal).toFixed(2)}).`,
              409,
            );
          }
          const waivedToApply =
            requestedWaivedAmount ?? roundCurrency(state.outstandingTotal);
          const row = await tx.lateFeeWaiver.create({
            data: {
              companyId: input.companyId,
              saleId: sale.id,
              saleSyncId: sale.syncId,
              installmentId: null,
              installmentSyncId: null,
              cutoffAt: cutoff,
              calculatedFee: decimal(state.grossTotal),
              waivedAmount: decimal(waivedToApply),
              reason,
              appliedByUserId: input.operatorUserId,
              idempotencyKey: operationKey,
            },
            select: { id: true },
          });
          const after = await resolveSaleLateFeeState(
            tx,
            input.companyId,
            sale,
            installments,
            cutoff,
          );
          return {
            response: {
              saleId: sale.id,
              saleSyncId: sale.syncId,
              waiverId: row.id,
              cutoffAt: cutoff.toISOString(),
              windowGrossLateFees: state.grossTotal,
              collectedLateFees: state.collectedTotal,
              waivedAmount: waivedToApply,
              requestedWaivedAmount,
              isPartial: requestedWaivedAmount !== null,
              outstandingBefore: state.outstandingTotal,
              outstandingAfter: after.outstandingTotal,
            } as unknown as Prisma.JsonObject,
            resourceType: "sale",
            resourceId: sale.id,
          };
        },
      }),
    );
  }

  async registerPayment(
    input: RegisterAuthoritativePaymentInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: "payment.register",
        requestPayload: input,
        run: async () => {
          const response = await registerPaymentInTransaction(tx, input);
          return {
            response,
            resourceType: "payment",
            resourceId: String(response.paymentIds),
          };
        },
      }),
    );
  }

  async annulPayment(
    input: AnnulAuthoritativePaymentInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: "payment.annul",
        requestPayload: input,
        run: async () => {
          const response = await annulPaymentInTransaction(tx, input);
          return {
            response,
            resourceType: "payment",
            resourceId: input.paymentId,
          };
        },
      }),
    );
  }

  /**
   * FASE 01C — Previsualizacion (solo lectura) de una correccion historica.
   *
   * Devuelve si la operacion es segura, el mensaje accionable y el impacto
   * financiero estimado. No escribe nada.
   */
  async previewPaymentCorrection(
    input: PreviewPaymentCorrectionInput,
  ): Promise<Prisma.JsonObject> {
    if (!isCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion no soportada.",
        400,
      );
    }
    return this.prisma.$transaction(async (tx) => {
      const payment = await loadCorrectionPayment(
        tx,
        input.companyId,
        input.paymentId,
      );
      const { decision, saleBalanceBefore } = await evaluateCorrection(
        tx,
        payment,
        input.action,
        { newDate: input.newDate, newAmount: input.newAmount },
      );
      return correctionResponse(payment, decision, saleBalanceBefore);
    });
  }

  /**
   * FASE 01C — Aplica una correccion historica.
   *
   * Garantias: transaccion unica, bloqueo financiero de la venta, idempotencia
   * por `operationKey`, control optimista de version y auditoria completa. Si
   * cualquier paso falla, la transaccion revierte por completo.
   */
  async applyPaymentCorrection(
    input: ApplyPaymentCorrectionInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    if (!isCorrectionAction(input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion de correccion no soportada.",
        400,
      );
    }
    const reason = String(input.reason ?? "").trim();
    if (!reason) {
      throw new AuthoritativeError(
        "CORRECTION_REASON_REQUIRED",
        "Indica el motivo de la correccion.",
        400,
      );
    }
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: `payment.correction.${input.action}`,
        requestPayload: {
          paymentId: input.paymentId,
          action: input.action,
          newDate: input.newDate ?? null,
          newAmount: input.newAmount ?? null,
          reason,
          performedByUserId: input.performedByUserId,
        },
        run: async () => {
          const initial = await loadCorrectionPayment(
            tx,
            input.companyId,
            input.paymentId,
          );
          await lockSaleForFinancialMutation(tx, initial.sale!.id);
          // Se relee bajo bloqueo: otro proceso pudo anular/corregir el pago.
          const payment = await loadCorrectionPayment(
            tx,
            input.companyId,
            input.paymentId,
          );
          if (
            input.expectedPaymentVersion != null &&
            payment.version !== input.expectedPaymentVersion
          ) {
            throw new AuthoritativeError(
              "PAYMENT_VERSION_CONFLICT",
              "El pago cambio desde que abriste el dialogo. Recarga el historial e intentalo de nuevo.",
              409,
            );
          }
          const { decision, saleBalanceBefore } = await evaluateCorrection(
            tx,
            payment,
            input.action,
            { newDate: input.newDate, newAmount: input.newAmount },
          );
          if (!decision.allowed) {
            throw new AuthoritativeError(
              decision.code,
              decision.message,
              409,
            );
          }

          let response: Prisma.JsonObject;
          if (input.action === "annul") {
            response = await annulPaymentInTransaction(
              tx,
              {
                companyId: input.companyId,
                paymentId: payment.id,
                annulledByUserId: input.performedByUserId,
                authorizedByUserId: null,
                reason,
                annulledAt: new Date(),
                idempotencyKey: operationKey,
              },
              { allowHistorical: true },
            );
          } else if (input.action === "change_date") {
            const newDate = parseDate(input.newDate, payment.paidAt ?? new Date());
            response = (await changePaymentDateInTransaction(
              tx,
              payment,
              newDate,
              reason,
              input.performedByUserId,
            )) as unknown as Prisma.JsonObject;
          } else {
            const newAmount = Number(input.newAmount);
            const newDate = parseDate(input.newDate, payment.paidAt ?? new Date());
            response = (await replacePaymentAmountInTransaction(
              tx,
              payment,
              newAmount,
              newDate,
              reason,
              input.performedByUserId,
            )) as unknown as Prisma.JsonObject;
          }

          return {
            response: {
              ...(response as Record<string, unknown>),
              correction: {
                action: input.action,
                code: decision.code,
                message: decision.message,
                reason,
                performedByUserId: input.performedByUserId,
                performedAt: new Date().toISOString(),
                saleBalanceBefore,
                saleBalanceAfter: roundCurrency(
                  saleBalanceBefore + decision.impact.amountRestoredToBalance,
                ),
              },
            } as unknown as Prisma.JsonObject,
            resourceType: "payment",
            resourceId: payment.id,
          };
        },
      }),
    );
  }

  /**
   * FASE 01D — Historial de correcciones (SOLO LECTURA, solo OWNER).
   *
   * Reconstruye la traza administrativa de un pago a partir de fuentes que ya
   * existen (no se inventa una tabla nueva): alta del pago, correcciones
   * auditadas en `raw.corrections`, anulacion en `raw.annulmentAudit`, registros
   * idempotentes en `AuthoritativeOperation` y pagos de reemplazo enlazados por
   * `reversesPaymentId`.
   */
  async getPaymentCorrectionHistory(input: {
    companyId: string;
    paymentId: string;
  }): Promise<Prisma.JsonObject> {
    const payment = await this.prisma.payment.findFirst({
      where: { id: input.paymentId, companyId: input.companyId },
      include: { sale: true, installment: true },
    });
    if (!payment || !payment.sale) {
      throw new AuthoritativeError(
        "PAYMENT_NOT_FOUND",
        "El pago seleccionado no existe.",
        404,
      );
    }
    const replacements = await this.prisma.payment.findMany({
      where: { companyId: input.companyId, reversesPaymentId: payment.id },
      select: {
        id: true,
        amount: true,
        paidAt: true,
        paymentType: true,
        annulledAt: true,
        createdAt: true,
      },
      orderBy: { createdAt: "asc" },
    });
    const operationIds = [payment.id, ...replacements.map((row) => row.id)];
    const operations = await this.prisma.authoritativeOperation.findMany({
      where: {
        companyId: input.companyId,
        resourceId: { in: operationIds },
        operationType: { startsWith: "payment.correction." },
      },
      select: {
        operationType: true,
        resourceId: true,
        createdAt: true,
        response: true,
      },
      orderBy: { createdAt: "asc" },
    });

    type Entry = Record<string, unknown>;
    const history: Entry[] = [
      {
        kind: "created",
        at: payment.createdAt.toISOString(),
        action: "register",
        amount: toNumber(payment.amount),
        paymentType: payment.paymentType,
        detail: "Pago registrado",
      },
    ];

    const raw = (payment.raw ?? {}) as Record<string, unknown>;
    if (Array.isArray(raw.corrections)) {
      for (const entry of raw.corrections as unknown[]) {
        if (entry && typeof entry === "object") {
          history.push({ kind: "correction", ...(entry as Entry) });
        }
      }
    }
    if (raw.annulmentAudit && typeof raw.annulmentAudit === "object") {
      const audit = raw.annulmentAudit as Entry;
      history.push({
        kind: "annulment",
        at: audit.annulledAt ?? null,
        action: "annul",
        reason: audit.reason ?? null,
        performedByUserId: audit.performedByUserId ?? null,
        authorizedByUserId: audit.authorizedByUserId ?? null,
        overridden: audit.override === true,
      });
    }
    for (const operation of operations) {
      const response = (operation.response ?? {}) as Record<string, unknown>;
      const correction = (response.correction ?? {}) as Record<string, unknown>;
      history.push({
        kind: "authoritative_operation",
        at: operation.createdAt.toISOString(),
        action: String(operation.operationType).replace(
          "payment.correction.",
          "",
        ),
        reason: correction.reason ?? null,
        performedByUserId: correction.performedByUserId ?? null,
        saleBalanceBefore: correction.saleBalanceBefore ?? null,
        saleBalanceAfter: correction.saleBalanceAfter ?? null,
        targetPaymentId: operation.resourceId,
      });
    }
    for (const replacement of replacements) {
      history.push({
        kind: "replacement",
        at: replacement.createdAt.toISOString(),
        action: "replacement_created",
        paymentId: replacement.id,
        amount: toNumber(replacement.amount),
        paidAt: replacement.paidAt?.toISOString() ?? null,
        paymentType: replacement.paymentType,
        annulledAt: replacement.annulledAt?.toISOString() ?? null,
      });
    }

    history.sort((a, b) =>
      String(a.at ?? "").localeCompare(String(b.at ?? "")),
    );

    return {
      payment: {
        id: payment.id,
        saleId: payment.sale.id,
        paymentType: payment.paymentType,
        amount: toNumber(payment.amount),
        paidAt: payment.paidAt?.toISOString() ?? null,
        createdAt: payment.createdAt.toISOString(),
        annulledAt: payment.annulledAt?.toISOString() ?? null,
        annulmentReason: payment.annulmentReason ?? null,
        version: payment.version,
        installmentNumber: payment.installment?.installmentNumber ?? null,
      },
      history,
    } as unknown as Prisma.JsonObject;
  }

  async settleSale(
    input: SettleSaleInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: "payment.settlement",
        requestPayload: input,
        run: async () => {
          const response = await settleSaleInTransaction(tx, input);
          return {
            response,
            resourceType: "payment",
            resourceId: String(response.paymentId),
          };
        },
      }),
    );
  }
}

/**
 * Serializa las mutaciones financieras de UNA venta.
 *
 * Sin este bloqueo, una condonacion y un pago concurrentes podian leer el mismo
 * estado: el pago cobraba la mora bruta y la condonacion la condonaba a la vez,
 * cobrando al cliente mora que se estaba perdonando. Todas las rutas que leen o
 * escriben mora de una venta toman primero este bloqueo, en el mismo orden, para
 * evitar interbloqueos.
 */
async function lockSaleForFinancialMutation(
  tx: TransactionClient,
  saleId: string,
): Promise<void> {
  await tx.$queryRaw`SELECT id FROM "Sale" WHERE id = ${saleId} FOR UPDATE`;
}

async function settleSaleInTransaction(
  tx: TransactionClient,
  input: SettleSaleInput,
): Promise<Prisma.JsonObject> {
  const now = new Date();
  const paymentDate = parseDate(input.paymentDate, now);
  const sale = await loadSale(tx, {
    companyId: input.companyId,
    receivedByUserId: input.receivedByUserId,
    idempotencyKey: input.idempotencyKey,
    saleId: input.saleId,
  });
  if ((sale.status ?? "") === "cancelada" || sale.deletedAt) {
    throw new AuthoritativeError(
      "SALE_STATUS_REJECTED",
      "La venta seleccionada no admite liquidacion.",
    );
  }
  await lockSaleForFinancialMutation(tx, sale.id);
  if (toNumber(sale.initialPendingAmount) > 0.009) {
    throw new AuthoritativeError(
      "INITIAL_PENDING_BLOCKS_SETTLEMENT",
      "Completa primero el inicial pendiente antes de saldar la deuda total.",
      409,
    );
  }

  const installments = await loadActiveInstallments(tx, sale.id);
  const lateFees = await resolveSettlementLateFees(
    tx,
    input.companyId,
    sale,
    installments,
    paymentDate,
  );
  const quote = buildSettlementQuoteResponse(
    sale,
    installments,
    paymentDate,
    lateFees,
  );
  if (quote.settlementAmount <= 0.009 || quote.isFullyPaid === true) {
    throw new AuthoritativeError(
      "SALE_ALREADY_PAID",
      "La venta seleccionada ya esta saldada.",
      409,
    );
  }
  if (input.quoteVersion && input.quoteVersion !== quote.quoteVersion) {
    throw new AuthoritativeError(
      "STALE_SETTLEMENT_QUOTE",
      "El saldo cambio. Revisa el monto actualizado antes de continuar.",
      409,
    );
  }

  const lotBefore = sale.lotId
    ? await tx.lot.findUnique({
        where: { id: sale.lotId },
        select: { id: true, status: true },
      })
    : null;
  const preSnapshot = buildSettlementPreSnapshot(sale, installments, lotBefore);
  for (const installment of installments) {
    if (isClosedStatus(installment.status ?? "")) {
      continue;
    }
    const due = isDueOnOrBeforeBusinessDate(installment.dueDate, paymentDate);
    if (due) {
      await tx.installment.update({
        where: { id: installment.id },
        data: {
          paidAmount: installment.totalAmount,
          paidPrincipalAmount: installment.principalAmount,
          paidInterestAmount: installment.interestAmount,
          status: "pagada",
          raw: mergeRaw(installment.raw, {
            settlementReason: "liquidacion_total",
          }),
          version: { increment: 1 },
        },
      });
    } else {
      await tx.installment.update({
        where: { id: installment.id },
        data: {
          openingBalance: decimal(0),
          principalAmount: decimal(0),
          interestAmount: decimal(0),
          totalAmount: decimal(0),
          paidAmount: decimal(0),
          paidPrincipalAmount: decimal(0),
          paidInterestAmount: decimal(0),
          endingBalance: decimal(0),
          status: "ajustada",
          raw: mergeRaw(installment.raw, {
            adjustmentReason: "liquidacion_total",
          }),
          version: { increment: 1 },
        },
      });
    }
  }

  const payment = await tx.payment.create({
    data: {
      companyId: input.companyId,
      syncId: newSyncId("payment"),
      saleId: sale.id,
      clientId: sale.clientId,
      receivedByUserId: input.receivedByUserId,
      saleSyncId: sale.syncId,
      clientSyncId: sale.clientSyncId,
      paidAt: paymentDate,
      amount: decimal(quote.settlementAmount),
      method: normalizePaymentMethod(input.paymentMethod),
      paymentType: "liquidacion_total",
      reference:
        input.reference ?? `SETTLEMENT-${sale.id}-${now.getTime().toString()}`,
      principalApplied: decimal(quote.principalOutstanding),
      interestApplied: decimal(quote.dueInterest),
      lateFeeApplied: decimal(quote.lateFees),
      raw: {
        authoritativeSource: "settlement",
        quote,
        preSnapshot,
      },
    },
    select: { id: true },
  });

  await tx.sale.update({
    where: { id: sale.id },
    data: {
      initialPendingAmount: decimal(0),
      balance: decimal(0),
      status: "pagada",
      raw: mergeRaw(sale.raw, {
        lastSettlementPaymentId: payment.id,
        futureInterestWaived: quote.futureInterestWaived,
      }),
      version: { increment: 1 },
    },
  });
  if (sale.lotId) {
    await tx.lot.update({
      where: { id: sale.lotId },
      data: { status: "vendido", version: { increment: 1 } },
    });
  }

  return {
    saleId: sale.id,
    paymentId: payment.id,
    status: "pagada",
    balance: 0,
    initialPendingAmount: 0,
    paymentType: "liquidacion_total",
    quote,
  };
}

async function registerPaymentInTransaction(
  tx: TransactionClient,
  input: RegisterAuthoritativePaymentInput,
): Promise<Prisma.JsonObject> {
  const now = new Date();
  const paymentDate = parseDate(input.paymentDate, now);
  const amountPaid = roundCurrency(input.amountPaid ?? input.amount ?? 0);
  if (amountPaid <= 0) {
    throw new AuthoritativeError(
      "INVALID_PAYMENT_AMOUNT",
      "El monto pagado debe ser mayor que cero.",
    );
  }

  const sale = await loadSale(tx, input);
  await lockSaleForFinancialMutation(tx, sale.id);
  const saleStatus = sale.status ?? "apartado";
  const paymentTypeOverride =
    input.paymentTypeOverride ?? input.paymentType ?? "cuota";
  const pendingInitial = toNumber(sale.initialPendingAmount);
  const pendingBalance = toNumber(sale.balance);
  const salePrice = toNumber(sale.total);
  const paidInitial = toNumber(sale.initialPaid);
  const requiredInitial = toNumber(sale.initialRequiredAmount);
  const monthlyInterest = toNumber(sale.monthlyInterestRate);
  const installmentCount = sale.installmentCount ?? 0;
  /**
   * FASE 3 — el calendario se ancla SIEMPRE en `saleDate`.
   *
   * Antes: `sale.saleDate ?? paymentDate`. Ese fallback permitia que anclar el
   * calendario a la FECHA DEL PAGO cuando la venta no tenia saleDate, que es
   * exactamente el defecto del incidente P0 (aplicar la inicial movia las cuotas
   * un mes). La fecha de pago NO es un ancla valida para un contrato.
   */
  const saleDate = sale.saleDate;
  if (!saleDate) {
    throw new AuthoritativeError(
      "SALE_DATE_REQUIRED_FOR_SCHEDULE",
      "La venta no tiene fecha de venta: no se puede generar ni recalcular el calendario de cuotas.",
      409,
    );
  }
  const paymentIds: string[] = [];

  if (pendingInitial <= 0.009 && pendingBalance <= 0.009) {
    throw new AuthoritativeError(
      "SALE_ALREADY_PAID",
      "La venta seleccionada ya no tiene saldo pendiente.",
      409,
    );
  }

  if (paymentTypeOverride === "abono_capital") {
    await assertCapitalPaymentAllowed(tx, sale.id, pendingInitial, paymentDate);
  }

  if (saleStatus === "apartado" || saleStatus === "inicial_incompleto") {
    const saleAmountRemaining = roundCurrency(
      Math.max(salePrice - paidInitial, 0),
    );
    const initialPaymentApplied = Math.min(amountPaid, saleAmountRemaining);
    if (initialPaymentApplied <= 0) {
      throw new AuthoritativeError(
        "NO_PAYMENT_IMPACT",
        "El pago no impacto la venta seleccionada.",
      );
    }

    const updatedInitialPaid = roundCurrency(
      paidInitial + initialPaymentApplied,
    );
    const updatedInitialPending = calculatePendingInitialPayment({
      requiredInitialPayment: requiredInitial,
      initialPaymentPaid: updatedInitialPaid,
    });
    const updatedFinancedBalance = calculateFinancedBalance({
      salePrice,
      downPaymentAmount: updatedInitialPaid,
    });
    const newStatus = resolveUpfrontSaleStatus({
      initialRequiredAmount: requiredInitial,
      initialPaidAmount: updatedInitialPaid,
      financedBalance: updatedFinancedBalance,
    });

    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId("payment"),
        saleId: sale.id,
        clientId: sale.clientId,
        receivedByUserId: input.receivedByUserId,
        saleSyncId: sale.syncId,
        clientSyncId: sale.clientSyncId,
        paidAt: paymentDate,
        amount: decimal(initialPaymentApplied),
        method: normalizePaymentMethod(input.paymentMethod),
        paymentType: paidInitial <= 0.009 ? "apartado" : "abono_inicial",
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(0),
        interestApplied: decimal(0),
        lateFeeApplied: decimal(0),
        raw: authoritativePaymentRaw(input.sourceSyncId),
      },
      select: { id: true },
    });
    paymentIds.push(payment.id);

    await tx.sale.update({
      where: { id: sale.id },
      data: {
        initialPaid: decimal(updatedInitialPaid),
        initialPendingAmount: decimal(updatedInitialPending),
        financedBalance: decimal(updatedFinancedBalance),
        balance: decimal(updatedFinancedBalance),
        status: newStatus,
        activationDate:
          newStatus === "activa" || newStatus === "pagada" ? paymentDate : null,
        version: { increment: 1 },
      },
    });

    if (sale.lotId) {
      await tx.lot.update({
        where: { id: sale.lotId },
        data: {
          status:
            newStatus === "activa" || newStatus === "pagada"
              ? "vendido"
              : "reservado",
          version: { increment: 1 },
        },
      });
    }

    await regenerateInstallmentsForActivatedSale(tx, sale, {
      paymentDate,
      newStatus,
      updatedFinancedBalance,
      monthlyInterest,
      installmentCount,
      saleDate,
    });

    if (roundCurrency(amountPaid - initialPaymentApplied) > 0.009) {
      throw new AuthoritativeError(
        "PAYMENT_EXCEEDS_BALANCE",
        "El pago excede el monto restante de la venta.",
      );
    }

    return {
      saleId: sale.id,
      paymentIds,
      status: newStatus,
      balance: updatedFinancedBalance,
      initialPaid: updatedInitialPaid,
      initialPendingAmount: updatedInitialPending,
    };
  }

  if (saleStatus !== "activa" && saleStatus !== "pagada") {
    throw new AuthoritativeError(
      "SALE_STATUS_REJECTED",
      "La venta seleccionada no admite pagos en su estado actual.",
    );
  }
  if (pendingBalance <= 0.009) {
    throw new AuthoritativeError(
      "SALE_PLAN_PAID",
      "La venta seleccionada ya no tiene saldo pendiente del plan.",
      409,
    );
  }

  const installments = await loadActiveInstallments(tx, sale.id);
  const lateFeePolicy = await readLateFeePolicy(
    tx,
    input.companyId,
    paymentDate,
  );
  const lateFeeCalculator = new LateFeeCalculationService({
    enabled: lateFeePolicy.enabled,
    dailyRate: lateFeePolicy.dailyRate,
    graceDays: lateFeePolicy.graceDays,
    timezone: BUSINESS_TIMEZONE,
  });
  const priorPayments = await tx.payment.findMany({
    where: {
      companyId: input.companyId,
      saleId: sale.id,
      deletedAt: null,
      annulledAt: null,
    },
    orderBy: [{ paidAt: "asc" }, { createdAt: "asc" }],
  });
  // Fase 1 (hardening): la condonacion a nivel de venta se asigna UNA sola vez
  // por cuota (`resolveSaleLateFeeState`). Antes se pasaba la lista completa de
  // condonaciones a cada cuota y el mismo monto se reutilizaba en varias.
  const saleLateFeeState = await resolveSaleLateFeeState(
    tx,
    input.companyId,
    sale,
    installments,
    paymentDate,
    { payments: priorPayments },
  );
  const outstandingPrincipal = calculateOutstandingPrincipal(installments);
  const fixedInstallmentAmount = calculateEstimatedInstallmentAmount({
    financedBalance: toNumber(sale.financedBalance),
    monthlyInterest,
    installmentCount,
  });
  if (paymentTypeOverride === "cuotas_adelantadas") {
    const hasOverdueInstallments = installments.some(
      (item) =>
        !isClosedStatus(item.status ?? "") &&
        remainingAmount(item) > 0.009 &&
        isPastDueBusinessDate(item.dueDate, paymentDate),
    );
    if (hasOverdueInstallments) {
      throw new AuthoritativeError(
        "ADVANCE_PAYMENT_BLOCKED_OVERDUE_INSTALLMENTS",
        "No puedes adelantar cuotas porque existen cuotas vencidas. Primero salda las cuotas atrasadas.",
        409,
      );
    }
  }
  const installmentsToProcess = resolveInstallmentsToProcess({
    installments,
    paymentDate,
    paymentTypeOverride,
    targetInstallmentId: input.targetInstallmentId ?? null,
    targetInstallmentNumber: input.targetInstallmentNumber ?? null,
    advanceInstallmentCount: input.advanceInstallmentCount ?? null,
  });
  const requiresInstallmentImpact = [
    "cuota",
    "cuota_vencida",
    "todas_cuotas_vencidas",
    "cuotas_adelantadas",
  ].includes(paymentTypeOverride);
  const openInstallmentIds = new Set(
    installments
      .filter(
        (item) =>
          !isClosedStatus(item.status ?? "") && remainingAmount(item) > 0.009,
      )
      .map((item) => item.id),
  );
  const selectedInstallmentIds = new Set(
    installmentsToProcess.map((item) => item.id),
  );

  let remaining = amountPaid;
  let totalPrincipalReduction = 0;
  let currentInstallmentNumber = 0;
  let installmentAppliedTotal = 0;
  const createdPaymentsForLateFee: typeof priorPayments = [];

  for (const installment of installmentsToProcess) {
    if (remaining <= 0.009) {
      break;
    }
    currentInstallmentNumber = installment.installmentNumber ?? 0;
    const lateFeeOutstanding = calculateInstallmentLateFeeOutstanding({
      calculator: lateFeeCalculator,
      installment,
      payments: [...priorPayments, ...createdPaymentsForLateFee],
      paymentDate,
      companyId: input.companyId,
      saleSyncId: sale.syncId,
      waivers: installmentWaiverFor(saleLateFeeState, installment.syncId),
    });
    const outcome = applyToInstallment(
      installment,
      remaining,
      paymentDate,
      lateFeeOutstanding,
    );
    if (outcome.appliedAmount <= 0) {
      continue;
    }

    await tx.installment.update({
      where: { id: installment.id },
      data: {
        paidAmount: decimal(outcome.newPaidAmount),
        paidPrincipalAmount: decimal(outcome.newPrincipalPaid),
        paidInterestAmount: decimal(outcome.newInterestPaid),
        status: outcome.newStatus,
        version: { increment: 1 },
      },
    });
    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId("payment"),
        saleId: sale.id,
        clientId: sale.clientId,
        installmentId: installment.id,
        receivedByUserId: input.receivedByUserId,
        saleSyncId: sale.syncId,
        clientSyncId: sale.clientSyncId,
        installmentSyncId: installment.syncId,
        paidAt: paymentDate,
        amount: decimal(outcome.appliedAmount),
        method: normalizePaymentMethod(input.paymentMethod),
        paymentType: "cuota",
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(outcome.principalPaidNow),
        interestApplied: decimal(outcome.interestPaidNow),
        lateFeeApplied: decimal(outcome.lateFeePaidNow),
        raw: authoritativePaymentRaw(input.sourceSyncId),
      },
      select: {
        id: true,
        companyId: true,
        saleId: true,
        installmentSyncId: true,
        paidAt: true,
        amount: true,
        principalApplied: true,
        interestApplied: true,
        lateFeeApplied: true,
        deletedAt: true,
        annulledAt: true,
        createdAt: true,
      },
    });
    paymentIds.push(payment.id);
    createdPaymentsForLateFee.push(payment as any);

    remaining = outcome.remainingAmount;
    installmentAppliedTotal = roundCurrency(
      installmentAppliedTotal + outcome.appliedAmount,
    );
    totalPrincipalReduction = roundCurrency(
      totalPrincipalReduction + outcome.principalPaidNow,
    );
  }

  if (requiresInstallmentImpact && installmentAppliedTotal <= 0.009) {
    throw new AuthoritativeError(
      "NO_INSTALLMENT_IMPACT",
      "El pago no impacto ninguna cuota elegible.",
    );
  }

  let capitalPrepayment = 0;
  if (remaining > 0.009) {
    const maxCapitalPayment = roundCurrency(
      outstandingPrincipal - totalPrincipalReduction,
    );
    if (maxCapitalPayment <= 0) {
      throw new AuthoritativeError(
        "PAYMENT_EXCEEDS_BALANCE",
        "El pago excede el saldo pendiente disponible.",
      );
    }
    capitalPrepayment = Math.min(remaining, maxCapitalPayment);
    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId("payment"),
        saleId: sale.id,
        clientId: sale.clientId,
        receivedByUserId: input.receivedByUserId,
        saleSyncId: sale.syncId,
        clientSyncId: sale.clientSyncId,
        paidAt: paymentDate,
        amount: decimal(capitalPrepayment),
        method: normalizePaymentMethod(input.paymentMethod),
        paymentType: "abono_capital",
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(capitalPrepayment),
        interestApplied: decimal(0),
        lateFeeApplied: decimal(0),
        raw: authoritativePaymentRaw(input.sourceSyncId),
      },
      select: { id: true },
    });
    paymentIds.push(payment.id);
    remaining = roundCurrency(remaining - capitalPrepayment);
    totalPrincipalReduction = roundCurrency(
      totalPrincipalReduction + capitalPrepayment,
    );
  }

  if (remaining > 0.009) {
    throw new AuthoritativeError(
      "PAYMENT_EXCEEDS_BALANCE",
      "El pago excede el saldo pendiente de la venta.",
    );
  }

  const settlesDisplayedBalance =
    paymentTypeOverride === "abono_capital" &&
    amountPaid >= pendingBalance - 0.009;
  const settlesAllInstallments =
    requiresInstallmentImpact &&
    remaining <= 0.009 &&
    openInstallmentIds.size > 0 &&
    [...openInstallmentIds].every((id) => selectedInstallmentIds.has(id));
  const remainingPrincipalBalance = settlesDisplayedBalance
    ? 0
    : roundCurrency(
        Math.min(
          Math.max(outstandingPrincipal - totalPrincipalReduction, 0),
          toNumber(sale.financedBalance),
        ),
      );

  await recalculateFutureInstallments(tx, {
    installments,
    paymentDate,
    currentInstallmentNumber,
    monthlyInterest,
    fixedInstallmentAmount,
    remainingPrincipalBalance,
    shouldRecalculate: capitalPrepayment > 0 || settlesDisplayedBalance,
  });

  if (settlesAllInstallments) {
    const stillOpen = await loadActiveInstallments(tx, sale.id);
    for (const installment of stillOpen) {
      if (
        ["pagada", "ajustada", "cancelada"].includes(installment.status ?? "")
      ) {
        continue;
      }
      await tx.installment.update({
        where: { id: installment.id },
        data: {
          paidAmount: installment.totalAmount,
          paidPrincipalAmount: installment.principalAmount,
          paidInterestAmount: installment.interestAmount,
          status: "pagada",
          version: { increment: 1 },
        },
      });
    }
  }

  const hasOpenInstallments = await hasOpenInstallmentBalance(tx, sale.id);
  const newPendingBalance =
    settlesDisplayedBalance || settlesAllInstallments || !hasOpenInstallments
      ? 0
      : await loadOutstandingContractBalance(tx, sale.id);
  const newStatus = newPendingBalance <= 0.009 ? "pagada" : "activa";

  await tx.sale.update({
    where: { id: sale.id },
    data: {
      balance: decimal(newPendingBalance),
      status: newStatus,
      version: { increment: 1 },
    },
  });

  return {
    saleId: sale.id,
    paymentIds,
    status: newStatus,
    balance: newPendingBalance,
    principalApplied: totalPrincipalReduction,
    capitalPrepayment,
  };
}

/**
 * Conserva el `raw` existente del pago y anexa la auditoria de anulacion.
 * `performedByUserId` es quien ejecuto la accion; `authorizedByUserId` es el
 * administrador que la autorizo cuando hubo override.
 */
function mergeAnnulmentAudit(
  raw: unknown,
  audit: Record<string, unknown>,
): Prisma.InputJsonValue {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  base.annulmentAudit = audit;
  return base as Prisma.InputJsonValue;
}

/**
 * Tipos de pago que NO admiten anulacion individual (FASE 01B, defecto P1).
 *
 * `contado` registra el cobro de una venta al contado con `installmentId=null`
 * y la venta ya queda `pagada` con balance 0. Anularlo no tiene cuota que
 * revertir ni deuda que restaurar: el pago quedaba anulado mientras la venta
 * seguia `pagada` y el solar `vendido`, borrando la evidencia del cobro sin
 * devolver la obligacion. Se rechaza de forma explicita y accionable.
 *
 * La via correcta para deshacer una venta al contado es anular/revertir la
 * venta completa desde Ventas (operacion con su propio motor y auditoria).
 */
export function paymentAnnulmentTypeRejection(
  paymentType: string | null | undefined,
): { code: string; message: string } | null {
  if ((paymentType ?? "").trim().toLowerCase() === "contado") {
    return {
      code: "CASH_SALE_PAYMENT_NOT_ANNULLABLE",
      message:
        "El cobro de una venta al contado no se puede anular individualmente: anula o revierte la venta completa desde Ventas.",
    };
  }
  return null;
}

async function annulPaymentInTransaction(
  tx: TransactionClient,
  input: AnnulAuthoritativePaymentInput,
  options: { allowHistorical?: boolean } = {},
): Promise<Prisma.JsonObject> {
  const annulledAt = parseDate(input.annulledAt, new Date());
  const payment = await tx.payment.findFirst({
    where: {
      id: input.paymentId,
      companyId: input.companyId,
    },
    include: { sale: true, installment: true },
  });
  if (!payment || !payment.sale) {
    throw new AuthoritativeError(
      "PAYMENT_NOT_FOUND",
      "El pago seleccionado no existe.",
      404,
    );
  }
  await lockSaleForFinancialMutation(tx, payment.sale.id);
  if (payment.annulledAt) {
    // Idempotencia de anulacion: nunca reversar dos veces el mismo pago.
    throw new AuthoritativeError(
      "PAYMENT_ALREADY_ANNULLED",
      "Este pago ya fue anulado.",
      409,
    );
  }
  if (payment.deletedAt) {
    throw new AuthoritativeError(
      "PAYMENT_NOT_FOUND",
      "El pago seleccionado no existe.",
      404,
    );
  }

  const typeRejection = paymentAnnulmentTypeRejection(payment.paymentType);
  if (typeRejection) {
    throw new AuthoritativeError(
      typeRejection.code,
      typeRejection.message,
      409,
    );
  }

  const latest = await tx.payment.findFirst({
    where: {
      companyId: input.companyId,
      saleId: payment.saleId,
      deletedAt: null,
      annulledAt: null,
    },
    orderBy: [{ paidAt: "desc" }, { createdAt: "desc" }, { id: "desc" }],
    select: { id: true },
  });
  // FASE 01C: la anulacion historica solo se habilita desde el motor de
  // correccion, que ANTES demuestra con `evaluatePaymentCorrection` que la
  // reconstruccion financiera es segura. La ruta normal conserva la regla LIFO.
  if (!options.allowHistorical && latest?.id !== payment.id) {
    throw new AuthoritativeError(
      "ONLY_LATEST_PAYMENT_CAN_BE_ANNULLED",
      "Solo se permite anular el ultimo pago activo de la venta.",
      409,
    );
  }

  const authorizedByUserId = input.authorizedByUserId ?? null;
  await tx.payment.update({
    where: { id: payment.id },
    data: {
      annulledAt,
      annulledByUserId: input.annulledByUserId,
      annulmentReason: input.reason ?? null,
      raw: mergeAnnulmentAudit(payment.raw, {
        performedByUserId: input.annulledByUserId,
        authorizedByUserId,
        reason: input.reason ?? null,
        annulledAt: annulledAt.toISOString(),
        override: authorizedByUserId !== null,
      }),
      deletedAt: annulledAt,
      version: { increment: 1 },
    },
  });

  const amount = toNumber(payment.amount);
  if (payment.installmentId && payment.installment) {
    const installment = payment.installment;
    const installmentReduction = roundCurrency(
      toNumber(payment.principalApplied) + toNumber(payment.interestApplied),
    );
    const newPaidAmount = roundCurrency(
      Math.max(toNumber(installment.paidAmount) - installmentReduction, 0),
    );
    const newPrincipalPaid = roundCurrency(
      Math.max(
        toNumber(installment.paidPrincipalAmount) -
          toNumber(payment.principalApplied),
        0,
      ),
    );
    const newInterestPaid = roundCurrency(
      Math.max(
        toNumber(installment.paidInterestAmount) -
          toNumber(payment.interestApplied),
        0,
      ),
    );
    await tx.installment.update({
      where: { id: installment.id },
      data: {
        paidAmount: decimal(newPaidAmount),
        paidPrincipalAmount: decimal(newPrincipalPaid),
        paidInterestAmount: decimal(newInterestPaid),
        status: resolveInstallmentStatus({
          dueDate: installment.dueDate ?? annulledAt,
          paidAmount: newPaidAmount,
          totalAmount: toNumber(installment.totalAmount),
          asOf: annulledAt,
        }),
        version: { increment: 1 },
      },
    });
  }

  if (
    payment.paymentType === "apartado" ||
    payment.paymentType === "abono_inicial"
  ) {
    const updatedSale = await reverseInitialPayment(
      tx,
      payment.sale,
      amount,
      annulledAt,
      payment.paymentType === "apartado",
    );
    return {
      paymentId: payment.id,
      saleId: payment.sale.id,
      status: updatedSale.status ?? null,
      balance: toNumber(updatedSale.balance),
      annulledAt: annulledAt.toISOString(),
      performedByUserId: input.annulledByUserId,
      authorizedByUserId,
    };
  } else if (payment.paymentType === "liquidacion_total") {
    await restoreSettlementPreSnapshot(tx, payment);
    return {
      paymentId: payment.id,
      saleId: payment.sale.id,
      status: snapshotSaleStatus(payment.raw) ?? "activa",
      balance: snapshotSaleBalance(payment.raw),
      annulledAt: annulledAt.toISOString(),
      performedByUserId: input.annulledByUserId,
      authorizedByUserId,
    };
  } else if (payment.paymentType === "abono_capital") {
    await reverseCapitalPayment(tx, payment.sale, amount, annulledAt);
  }

  const newBalance = await loadOutstandingContractBalance(tx, payment.sale.id);
  const updatedSale = await tx.sale.update({
    where: { id: payment.sale.id },
    data: {
      balance: decimal(newBalance),
      status:
        newBalance <= 0.009 &&
        toNumber(payment.sale.initialPendingAmount) <= 0.009
          ? "pagada"
          : payment.sale.status === "pagada"
            ? "activa"
            : payment.sale.status,
      version: { increment: 1 },
    },
    select: { id: true, status: true, balance: true },
  });

  return {
    paymentId: payment.id,
    saleId: payment.sale.id,
    status: updatedSale.status ?? null,
    balance: toNumber(updatedSale.balance),
    annulledAt: annulledAt.toISOString(),
    performedByUserId: input.annulledByUserId,
    authorizedByUserId,
  };
}

/* ─────────────────────────────────────────────────────────────────────────────
 * FASE 01C — Motor de correccion de pagos historicos
 *
 * `previewPaymentCorrection` calcula el impacto sin escribir nada.
 * `applyPaymentCorrection` aplica la correccion en UNA transaccion, con bloqueo
 * financiero de la venta, idempotencia por `operationKey`, control de version
 * opcional y auditoria en `Payment.raw.corrections` + `AuthoritativeOperation`.
 *
 * La decision de seguridad es PURA (`services/paymentCorrection.ts`): si la
 * reconstruccion no es demostrable, se rechaza con un mensaje accionable.
 * ────────────────────────────────────────────────────────────────────────── */

export type PreviewPaymentCorrectionInput = {
  companyId: string;
  paymentId: string;
  action: CorrectionAction;
  newDate?: string | Date | null;
  newAmount?: number | null;
};

export type ApplyPaymentCorrectionInput = PreviewPaymentCorrectionInput & {
  performedByUserId: string;
  reason: string;
  idempotencyKey: string;
  /** Version esperada del pago (control optimista). */
  expectedPaymentVersion?: number | null;
};

/** Une la auditoria de la correccion dentro del JSON `raw` existente. */
function appendCorrectionAudit(
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
  const history = [...previous, entry].slice(-20);
  base.corrections = history;
  return base as Prisma.InputJsonValue;
}

async function loadCorrectionPayment(
  tx: TransactionClient,
  companyId: string,
  paymentId: string,
) {
  const payment = await tx.payment.findFirst({
    where: { id: paymentId, companyId },
    include: { sale: true, installment: true },
  });
  if (!payment || !payment.sale) {
    throw new AuthoritativeError(
      "PAYMENT_NOT_FOUND",
      "El pago seleccionado no existe.",
      404,
    );
  }
  return payment;
}

type CorrectionPayment = Awaited<ReturnType<typeof loadCorrectionPayment>>;

async function buildCorrectionSnapshot(
  tx: TransactionClient,
  payment: CorrectionPayment,
  action: CorrectionAction,
  params: { newDate?: string | Date | null; newAmount?: number | null },
): Promise<CorrectionSnapshot> {
  const sale = payment.sale!;
  const reference = payment.paidAt ?? payment.createdAt;
  const laterPayments = await tx.payment.count({
    where: {
      companyId: payment.companyId,
      saleId: sale.id,
      deletedAt: null,
      annulledAt: null,
      id: { not: payment.id },
      paidAt: { not: null },
      OR: [
        { paidAt: { gt: reference } },
        { paidAt: reference, id: { gt: payment.id } },
      ],
    },
  });
  const activeInstallments = await tx.installment.count({
    where: { companyId: payment.companyId, saleId: sale.id, deletedAt: null },
  });
  return {
    action,
    paymentType: payment.paymentType,
    amount: toNumber(payment.amount),
    principalApplied: toNumber(payment.principalApplied),
    interestApplied: toNumber(payment.interestApplied),
    lateFeeApplied: toNumber(payment.lateFeeApplied),
    paidAt: reference,
    isAnnulled: payment.annulledAt !== null || payment.deletedAt !== null,
    saleStatus: sale.status ?? null,
    saleDate: sale.saleDate ?? null,
    hasLaterActivePayments: laterPayments > 0,
    hasActiveInstallments: activeInstallments > 0,
    hasInstallment: payment.installmentId !== null,
    installment: payment.installment
      ? {
          totalAmount: toNumber(payment.installment.totalAmount),
          paidAmount: toNumber(payment.installment.paidAmount),
          paidPrincipalAmount: toNumber(payment.installment.paidPrincipalAmount),
          paidInterestAmount: toNumber(payment.installment.paidInterestAmount),
          recalculatedAfterPayment: payment.installment.version > 1,
        }
      : null,
    newDate: params.newDate ? parseDate(params.newDate, reference) : null,
    newAmount: params.newAmount ?? null,
    now: new Date(),
  };
}

/**
 * Evalua la correccion y devuelve la decision junto con el saldo REAL de la
 * venta antes de tocar nada.
 */
async function evaluateCorrection(
  tx: TransactionClient,
  payment: CorrectionPayment,
  action: CorrectionAction,
  params: { newDate?: string | Date | null; newAmount?: number | null },
) {
  const snapshot = await buildCorrectionSnapshot(tx, payment, action, params);
  const decision = evaluatePaymentCorrection(snapshot);
  const saleBalanceBefore = await loadOutstandingContractBalance(
    tx,
    payment.sale!.id,
  );
  return { snapshot, decision, saleBalanceBefore };
}

function correctionResponse(
  payment: CorrectionPayment,
  decision: CorrectionDecision,
  saleBalanceBefore: number,
) {
  const restored = decision.impact.amountRestoredToBalance;
  return {
    payment: {
      id: payment.id,
      paymentType: payment.paymentType,
      amount: toNumber(payment.amount),
      paidAt: payment.paidAt?.toISOString() ?? null,
      createdAt: payment.createdAt.toISOString(),
      principalApplied: toNumber(payment.principalApplied),
      interestApplied: toNumber(payment.interestApplied),
      lateFeeApplied: toNumber(payment.lateFeeApplied),
      annulledAt: payment.annulledAt?.toISOString() ?? null,
      version: payment.version,
    },
    sale: {
      id: payment.sale!.id,
      status: payment.sale!.status ?? null,
      balance: saleBalanceBefore,
    },
    correction: {
      allowed: decision.allowed,
      code: decision.code,
      message: decision.message,
      requiresScheduleReconstruction: decision.requiresScheduleReconstruction,
      createsReplacementPayment: decision.createsReplacementPayment,
    },
    impact: {
      ...decision.impact,
      saleBalanceBefore,
      saleBalanceAfter: roundCurrency(saleBalanceBefore + restored),
      impactEstimated: true,
    },
  } as unknown as Prisma.JsonObject;
}

/** Cambia SOLO la fecha efectiva (`paidAt`), preservando `createdAt`. */
async function changePaymentDateInTransaction(
  tx: TransactionClient,
  payment: CorrectionPayment,
  newDate: Date,
  reason: string,
  performedByUserId: string,
) {
  const performedAt = new Date();
  await tx.payment.update({
    where: { id: payment.id },
    data: {
      paidAt: newDate,
      raw: appendCorrectionAudit(payment.raw, {
        action: "change_date",
        performedByUserId,
        reason,
        performedAt: performedAt.toISOString(),
        previousPaidAt: payment.paidAt?.toISOString() ?? null,
        newPaidAt: newDate.toISOString(),
        createdAtPreserved: payment.createdAt.toISOString(),
      }),
      version: { increment: 1 },
    },
  });
  if (payment.installment) {
    const installment = payment.installment;
    const status = resolveInstallmentStatus({
      dueDate: installment.dueDate ?? newDate,
      paidAmount: toNumber(installment.paidAmount),
      totalAmount: toNumber(installment.totalAmount),
      asOf: newDate,
    });
    if (status !== installment.status) {
      await tx.installment.update({
        where: { id: installment.id },
        data: { status, version: { increment: 1 } },
      });
    }
  }
  return {
    paymentId: payment.id,
    saleId: payment.sale!.id,
    action: "change_date",
    paidAt: newDate.toISOString(),
    createdAt: payment.createdAt.toISOString(),
    version: payment.version + 1,
  };
}

/**
 * Corrige el MONTO de un pago de cuota mediante anulacion + reemplazo.
 *
 * Nunca reescribe el monto de una fila existente: conserva el evento original
 * (anulado, con motivo) y registra un pago nuevo generado por el motor
 * financiero, enlazado con `reversesPaymentId` para trazabilidad.
 */
async function replacePaymentAmountInTransaction(
  tx: TransactionClient,
  payment: CorrectionPayment,
  newAmount: number,
  newDate: Date,
  reason: string,
  performedByUserId: string,
) {
  const sale = payment.sale!;
  const annulled = await annulPaymentInTransaction(
    tx,
    {
      companyId: payment.companyId,
      paymentId: payment.id,
      annulledByUserId: performedByUserId,
      authorizedByUserId: null,
      reason: `Correccion de monto: ${reason}`,
      annulledAt: new Date(),
      idempotencyKey: `correction-annul-${payment.id}`,
    },
    { allowHistorical: true },
  );

  const registration = await registerPaymentInTransaction(tx, {
    companyId: payment.companyId,
    receivedByUserId: payment.receivedByUserId ?? performedByUserId,
    idempotencyKey: `correction-${payment.id}`,
    saleId: sale.id,
    paymentDate: newDate,
    amountPaid: roundCurrency(newAmount),
    paymentMethod: payment.method ?? null,
    paymentTypeOverride: "cuota",
    yearToPay: payment.yearToPay ?? null,
    sourceSyncId: payment.syncId,
  });

  const createdIds = Array.isArray(
    (registration as Record<string, unknown>).paymentIds,
  )
    ? ((registration as Record<string, unknown>).paymentIds as string[])
    : [];
  for (const id of createdIds) {
    const created = await tx.payment.findUnique({
      where: { id },
      select: { id: true, raw: true },
    });
    if (!created) continue;
    await tx.payment.update({
      where: { id: created.id },
      data: {
        reversesPaymentId: payment.id,
        raw: appendCorrectionAudit(created.raw, {
          action: "replacement",
          replacesPaymentId: payment.id,
          performedByUserId,
          reason,
          performedAt: new Date().toISOString(),
        }),
      },
    });
  }

  return {
    paymentId: payment.id,
    saleId: sale.id,
    action: "correct_amount",
    previousAmount: toNumber(payment.amount),
    newAmount: roundCurrency(newAmount),
    replacementPaymentIds: createdIds,
    annulment: annulled,
    registration,
  };
}

function buildSettlementQuoteResponse(
  sale: Awaited<ReturnType<typeof loadSale>>,
  installments: LoadedInstallment[],
  asOfDate: Date,
  /** Mora exigible al corte (ya neta de condonaciones y de mora cobrada). */
  collectibleLateFees = 0,
) {
  const open = installments.filter(
    (item) => !isClosedStatus(item.status ?? ""),
  );
  const principalOutstanding = roundCurrency(
    open.reduce(
      (sum, item) =>
        sum +
        Math.max(
          toNumber(item.principalAmount) - toNumber(item.paidPrincipalAmount),
          0,
        ),
      0,
    ),
  );
  const dueInterest = roundCurrency(
    open
      .filter((item) => isDueOnOrBeforeBusinessDate(item.dueDate, asOfDate))
      .reduce(
        (sum, item) =>
          sum +
          Math.max(
            toNumber(item.interestAmount) - toNumber(item.paidInterestAmount),
            0,
          ),
        0,
      ),
  );
  const futureInterestWaived = roundCurrency(
    open
      .filter((item) => isAfterBusinessDate(item.dueDate, asOfDate))
      .reduce(
        (sum, item) =>
          sum +
          Math.max(
            toNumber(item.interestAmount) - toNumber(item.paidInterestAmount),
            0,
          ),
        0,
      ),
  );
  const lateFees = roundCurrency(Math.max(collectibleLateFees, 0));
  const settlementAmount = roundCurrency(
    principalOutstanding + dueInterest + lateFees,
  );
  const fingerprint = [
    sale.id,
    sale.version,
    toNumber(sale.balance).toFixed(2),
    toNumber(sale.initialPendingAmount).toFixed(2),
    lateFees.toFixed(2),
    ...installments.map((item) =>
      [
        item.id,
        item.version,
        item.status ?? "",
        toNumber(item.principalAmount).toFixed(2),
        toNumber(item.interestAmount).toFixed(2),
        toNumber(item.paidPrincipalAmount).toFixed(2),
        toNumber(item.paidInterestAmount).toFixed(2),
        toNumber(item.paidAmount).toFixed(2),
      ].join(":"),
    ),
  ].join("|");
  return {
    saleId: sale.id,
    asOfDate: asOfDate.toISOString(),
    principalOutstanding,
    dueInterest,
    lateFees,
    futureInterestWaived,
    settlementAmount,
    quoteVersion: Buffer.from(fingerprint).toString("base64url"),
    isFullyPaid:
      toNumber(sale.initialPendingAmount) <= 0.009 &&
      settlementAmount <= 0.009 &&
      (sale.status ?? "") === "pagada",
  };
}

export function buildSettlementQuoteForTest(input: {
  sale: Awaited<ReturnType<typeof loadSale>>;
  installments: LoadedInstallment[];
  asOfDate: Date;
  collectibleLateFees?: number;
}) {
  return buildSettlementQuoteResponse(
    input.sale,
    input.installments,
    input.asOfDate,
    input.collectibleLateFees ?? 0,
  );
}

type LateFeePaymentRow = {
  installmentSyncId: string | null;
  paidAt: Date | null;
  amount: Prisma.Decimal | number | string;
  principalApplied: Prisma.Decimal | number | string | null;
  interestApplied: Prisma.Decimal | number | string | null;
  lateFeeApplied: Prisma.Decimal | number | string | null;
  deletedAt: Date | null;
};

export type SaleLateFeeState = {
  policyEnabled: boolean;
  grossTotal: number;
  collectedTotal: number;
  waivedTotal: number;
  outstandingTotal: number;
  /** Mora condonada imputada a cada cuota (asignacion UNICA por cuota). */
  waivedByInstallment: Map<string, number>;
  /** Mora bruta acumulada por cuota. */
  grossByInstallment: Map<string, number>;
  /** Mora exigible por cuota (neta de condonacion y de mora ya cobrada). */
  outstandingByInstallment: Map<string, number>;
  /** Detalle por cuota, listo para presentacion. */
  installments: Array<{
    installmentSyncId: string;
    installmentNumber: number | null;
    dueDate: string | null;
    grossLateFee: number;
    waivedLateFee: number;
    collectedLateFee: number;
    outstandingLateFee: number;
  }>;
};

/**
 * Fase 1 (hardening) — Estado de mora de la VENTA en un corte.
 *
 * Punto UNICO de asignacion de condonaciones. La condonacion a nivel de venta
 * (`installmentSyncId` nulo) se asigna UNA sola vez, en orden cronologico, y se
 * expone por cuota en `waivedByInstallment`. Antes, el pago autoritativo pasaba
 * la lista completa de condonaciones a cada cuota, reutilizando el mismo monto
 * varias veces cuando habia varias cuotas vencidas.
 */
async function resolveSaleLateFeeState(
  tx: TransactionClient,
  companyId: string,
  sale: Awaited<ReturnType<typeof loadSale>>,
  installments: LoadedInstallment[],
  calculationDate: Date,
  options: { payments?: ReadonlyArray<LateFeePaymentRow> } = {},
): Promise<SaleLateFeeState> {
  const policy = await readLateFeePolicy(tx, companyId, calculationDate);
  if (!policy.enabled) {
    return {
      policyEnabled: false,
      grossTotal: 0,
      collectedTotal: 0,
      waivedTotal: 0,
      outstandingTotal: 0,
      waivedByInstallment: new Map(),
      grossByInstallment: new Map(),
      outstandingByInstallment: new Map(),
      installments: [],
    };
  }

  const calculator = new LateFeeCalculationService({
    enabled: policy.enabled,
    dailyRate: policy.dailyRate,
    graceDays: policy.graceDays,
    timezone: BUSINESS_TIMEZONE,
  });
  const payments =
    options.payments ??
    (await tx.payment.findMany({
      where: {
        companyId,
        saleId: sale.id,
        deletedAt: null,
        annulledAt: null,
      },
      select: {
        installmentSyncId: true,
        paidAt: true,
        amount: true,
        principalApplied: true,
        interestApplied: true,
        lateFeeApplied: true,
        deletedAt: true,
      },
      orderBy: [{ paidAt: "asc" }, { createdAt: "asc" }],
    }));
  const waivers = await loadSaleLateFeeWaivers(tx, companyId, sale.id);

  const summary = calculator.calculateSaleSummary({
    context: { companyId, saleSyncId: sale.syncId },
    installments,
    payments: [...payments],
    waivers,
    calculationDate,
  });

  const collectedByInstallment = new Map<string, number>();
  let collectedTotal = 0;
  for (const payment of payments) {
    const amount = toNumber(payment.lateFeeApplied);
    collectedTotal = roundCurrency(collectedTotal + amount);
    const key = payment.installmentSyncId;
    if (!key) continue;
    collectedByInstallment.set(key, (collectedByInstallment.get(key) ?? 0) + amount);
  }

  const waivedByInstallment = new Map<string, number>();
  const grossByInstallment = new Map<string, number>();
  const outstandingByInstallment = new Map<string, number>();
  const installmentsDetail: SaleLateFeeState["installments"] = [];
  let grossTotal = 0;
  let waivedTotal = 0;
  let outstandingTotal = 0;
  for (const cuota of summary.cuotas) {
    const key = cuota.cuotaSyncId;
    const gross = toNumber(cuota.moraBruta ?? cuota.mora);
    const waived = toNumber(cuota.moraCondonada ?? 0);
    const net = toNumber(cuota.mora);
    const collected = collectedByInstallment.get(key) ?? 0;
    const outstanding = Math.max(net - collected, 0);
    grossByInstallment.set(key, gross);
    waivedByInstallment.set(key, waived);
    outstandingByInstallment.set(key, roundCurrency(outstanding));
    installmentsDetail.push({
      installmentSyncId: key,
      installmentNumber: cuota.numeroCuota ?? null,
      dueDate: cuota.fechaVencimiento ?? null,
      grossLateFee: roundCurrency(gross),
      waivedLateFee: roundCurrency(waived),
      collectedLateFee: roundCurrency(collected),
      outstandingLateFee: roundCurrency(outstanding),
    });
    grossTotal = roundCurrency(grossTotal + gross);
    waivedTotal = roundCurrency(waivedTotal + waived);
    outstandingTotal = roundCurrency(outstandingTotal + outstanding);
  }

  return {
    policyEnabled: true,
    grossTotal,
    collectedTotal,
    waivedTotal,
    outstandingTotal,
    waivedByInstallment,
    grossByInstallment,
    outstandingByInstallment,
    installments: installmentsDetail,
  };
}

/**
 * Fase 2 — Estado de mora EXIGIBLE al corte para una liquidacion total.
 *
 * Reutiliza el mismo motor (`LateFeeCalculationService`) que el pago
 * autoritativo, la condonacion administrativa y los recordatorios. No duplica
 * formulas ni altera la politica global.
 *
 * Reglas:
 * - Mora bruta/condonada por cuota = `cuota.mora` del motor (ya descuenta las
 *   condonaciones persistidas en `LateFeeWaiver`).
 * - Se resta la mora YA COBRADA de esa cuota (`Payment.lateFeeApplied`) para no
 *   cobrar dos veces.
 * - Nunca negativo.
 */
async function resolveSettlementLateFees(
  tx: TransactionClient,
  companyId: string,
  sale: Awaited<ReturnType<typeof loadSale>>,
  installments: LoadedInstallment[],
  asOfDate: Date,
): Promise<number> {
  const state = await resolveSaleLateFeeState(
    tx,
    companyId,
    sale,
    installments,
    asOfDate,
  );
  return state.outstandingTotal;
}

function buildSettlementPreSnapshot(
  sale: Awaited<ReturnType<typeof loadSale>>,
  installments: LoadedInstallment[],
  lot: { id: string; status: string | null } | null,
) {
  return {
    sale: {
      id: sale.id,
      status: sale.status,
      balance: toNumber(sale.balance),
      initialPendingAmount: toNumber(sale.initialPendingAmount),
      initialPaid: toNumber(sale.initialPaid),
      financedBalance: toNumber(sale.financedBalance),
      raw: sale.raw ?? null,
      version: sale.version,
      lotId: sale.lotId,
    },
    installments: installments.map((item) => ({
      id: item.id,
      openingBalance: toNumber(item.openingBalance),
      principalAmount: toNumber(item.principalAmount),
      interestAmount: toNumber(item.interestAmount),
      totalAmount: toNumber(item.totalAmount),
      paidAmount: toNumber(item.paidAmount),
      paidPrincipalAmount: toNumber(item.paidPrincipalAmount),
      paidInterestAmount: toNumber(item.paidInterestAmount),
      endingBalance: toNumber(item.endingBalance),
      status: item.status,
      raw: item.raw ?? null,
      version: item.version,
    })),
    lot: lot ? { id: lot.id, status: lot.status } : null,
  };
}

async function restoreSettlementPreSnapshot(
  tx: TransactionClient,
  payment: Prisma.PaymentGetPayload<{
    include: { sale: true; installment: true };
  }>,
) {
  const snapshot = readSettlementSnapshot(payment.raw);
  if (!snapshot?.sale) {
    throw new AuthoritativeError(
      "SETTLEMENT_SNAPSHOT_MISSING",
      "No se encontro el snapshot financiero para anular esta liquidacion.",
      409,
    );
  }
  await tx.sale.update({
    where: { id: String(snapshot.sale.id) },
    data: {
      status: stringOrNull(snapshot.sale.status) ?? "activa",
      balance: decimal(toNumber(snapshot.sale.balance)),
      initialPendingAmount: decimal(
        toNumber(snapshot.sale.initialPendingAmount),
      ),
      initialPaid: decimal(toNumber(snapshot.sale.initialPaid)),
      financedBalance: decimal(toNumber(snapshot.sale.financedBalance)),
      raw: (snapshot.sale.raw ?? Prisma.JsonNull) as Prisma.InputJsonValue,
      version: { increment: 1 },
    },
  });
  for (const item of snapshot.installments ?? []) {
    await tx.installment.update({
      where: { id: String(item.id) },
      data: {
        openingBalance: decimal(toNumber(item.openingBalance)),
        principalAmount: decimal(toNumber(item.principalAmount)),
        interestAmount: decimal(toNumber(item.interestAmount)),
        totalAmount: decimal(toNumber(item.totalAmount)),
        paidAmount: decimal(toNumber(item.paidAmount)),
        paidPrincipalAmount: decimal(toNumber(item.paidPrincipalAmount)),
        paidInterestAmount: decimal(toNumber(item.paidInterestAmount)),
        endingBalance: decimal(toNumber(item.endingBalance)),
        status: stringOrNull(item.status),
        raw: (item.raw ?? Prisma.JsonNull) as Prisma.InputJsonValue,
        version: { increment: 1 },
      },
    });
  }
  const snapshotLot = readSnapshotLot(payment.raw);
  if (snapshotLot?.id) {
    await tx.lot.update({
      where: { id: String(snapshotLot.id) },
      data: {
        status: stringOrNull(snapshotLot.status),
        version: { increment: 1 },
      },
    });
  }
}

function readSettlementSnapshot(raw: unknown) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }
  const snapshot = (raw as Record<string, unknown>).preSnapshot;
  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    return null;
  }
  return snapshot as {
    sale?: Record<string, unknown>;
    installments?: Array<Record<string, unknown>>;
    lot?: Record<string, unknown> | null;
  };
}

function readSnapshotLot(raw: unknown) {
  const lot = readSettlementSnapshot(raw)?.lot;
  return lot && typeof lot === "object" && !Array.isArray(lot) ? lot : null;
}

function snapshotSaleStatus(raw: unknown) {
  return stringOrNull(readSettlementSnapshot(raw)?.sale?.status);
}

function snapshotSaleBalance(raw: unknown) {
  return toNumber(readSettlementSnapshot(raw)?.sale?.balance);
}

function mergeRaw(
  raw: unknown,
  patch: Record<string, unknown>,
): Prisma.InputJsonValue {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  return { ...base, ...patch } as Prisma.InputJsonValue;
}

function stringOrNull(value: unknown) {
  return typeof value === "string" ? value : null;
}

async function loadSale(
  tx: TransactionClient,
  input: RegisterAuthoritativePaymentInput,
) {
  const sale = input.saleId
    ? await tx.sale.findFirst({
        where: {
          id: input.saleId,
          companyId: input.companyId,
          deletedAt: null,
        },
      })
    : input.saleSyncId
      ? await tx.sale.findUnique({
          where: {
            companyId_syncId: {
              companyId: input.companyId,
              syncId: input.saleSyncId,
            },
          },
        })
      : null;
  if (!sale || sale.deletedAt) {
    throw new AuthoritativeError(
      "SALE_NOT_FOUND",
      "La venta seleccionada no existe.",
      404,
    );
  }
  return sale;
}

async function loadActiveInstallments(tx: TransactionClient, saleId: string) {
  return tx.installment.findMany({
    where: { saleId, deletedAt: null },
    orderBy: { installmentNumber: "asc" },
  });
}

async function assertCapitalPaymentAllowed(
  tx: TransactionClient,
  saleId: string,
  pendingInitial: number,
  paymentDate: Date,
) {
  if (pendingInitial > 0.009) {
    throw new AuthoritativeError(
      "CAPITAL_PAYMENT_BLOCKED_INITIAL_PENDING",
      "No puedes aplicar pago a capital porque este cliente tiene un inicial pendiente. Primero debes completar el pago inicial.",
      409,
    );
  }
  const openInstallments = await tx.installment.findMany({
    where: {
      saleId,
      deletedAt: null,
      status: { notIn: ["pagada", "ajustada", "cancelada"] },
    },
  });
  const overdue = openInstallments.find(
    (item) =>
      item.dueDate &&
      isPastDueBusinessDay({
        dueDate: item.dueDate,
        businessDate: paymentDate,
        timezone: BUSINESS_TIMEZONE,
      }) &&
      remainingAmount(item) > 0.009,
  );
  if (overdue && remainingAmount(overdue) > 0.009) {
    throw new AuthoritativeError(
      "CAPITAL_PAYMENT_BLOCKED_OVERDUE_INSTALLMENTS",
      "No puedes aplicar pago a capital porque este cliente tiene cuotas vencidas. Primero debes saldar las cuotas atrasadas.",
      409,
    );
  }
}

export function applyToInstallment(
  installment: LoadedInstallment,
  amount: number,
  asOf: Date,
  lateFeeOutstanding = 0,
) {
  const installmentRemaining = remainingAmount(installment);
  const lateFeePaidNow = roundCurrency(
    Math.min(amount, Math.max(lateFeeOutstanding, 0)),
  );
  const amountAfterLateFee = roundCurrency(amount - lateFeePaidNow);
  const appliedToInstallment =
    amountAfterLateFee > installmentRemaining
      ? installmentRemaining
      : amountAfterLateFee;
  const interestRemaining =
    toNumber(installment.interestAmount) -
    toNumber(installment.paidInterestAmount);
  const interestPaidNow =
    appliedToInstallment > interestRemaining
      ? interestRemaining
      : appliedToInstallment;
  const principalPaidNow = roundCurrency(
    appliedToInstallment - interestPaidNow,
  );
  const newPaidAmount = roundCurrency(
    toNumber(installment.paidAmount) + appliedToInstallment,
  );
  const newInterestPaid = roundCurrency(
    toNumber(installment.paidInterestAmount) + interestPaidNow,
  );
  const newPrincipalPaid = roundCurrency(
    toNumber(installment.paidPrincipalAmount) + principalPaidNow,
  );
  const appliedAmount = roundCurrency(lateFeePaidNow + appliedToInstallment);

  return {
    appliedAmount,
    lateFeePaidNow,
    principalPaidNow,
    interestPaidNow: roundCurrency(interestPaidNow),
    newPaidAmount,
    newInterestPaid,
    newPrincipalPaid,
    remainingAmount: roundCurrency(amount - appliedAmount),
    newStatus: resolveInstallmentStatus({
      dueDate: installment.dueDate ?? asOf,
      paidAmount: newPaidAmount,
      totalAmount: toNumber(installment.totalAmount),
      asOf,
    }),
  };
}

/**
 * Condonacion que corresponde a UNA cuota segun la asignacion ya calculada.
 * Se entrega como condonacion por cuota para que nunca se reutilice el monto.
 */
function installmentWaiverFor(
  state: SaleLateFeeState,
  installmentSyncId: string | null,
): Array<{ installmentSyncId: string; waivedAmount: number }> {
  if (!installmentSyncId) return [];
  const waived = state.waivedByInstallment.get(installmentSyncId) ?? 0;
  if (waived <= 0) return [];
  return [{ installmentSyncId, waivedAmount: waived }];
}

function calculateInstallmentLateFeeOutstanding(input: {
  calculator: LateFeeCalculationService;
  installment: LoadedInstallment;
  payments: Array<{
    installmentSyncId?: string | null;
    paidAt?: Date | null;
    amount?: Prisma.Decimal | number | string | null;
    principalApplied?: Prisma.Decimal | number | string | null;
    interestApplied?: Prisma.Decimal | number | string | null;
    lateFeeApplied?: Prisma.Decimal | number | string | null;
    deletedAt?: Date | null;
    annulledAt?: Date | null;
  }>;
  paymentDate: Date;
  companyId: string;
  saleSyncId: string;
  /** Fase 3: condonaciones de mora vigentes para la venta. */
  waivers?: Array<{
    installmentSyncId?: string | null;
    waivedAmount?: Prisma.Decimal | number | string | null;
    cutoffAt?: Date | null;
  }>;
}) {
  const relatedPayments = input.payments.filter(
    (payment) =>
      payment.installmentSyncId === input.installment.syncId &&
      !payment.deletedAt &&
      !payment.annulledAt,
  );
  const summary = input.calculator.calculateSaleSummary({
    context: {
      companyId: input.companyId,
      saleSyncId: input.saleSyncId,
    },
    installments: [input.installment],
    payments: relatedPayments,
    waivers: input.waivers,
    calculationDate: input.paymentDate,
  });
  const accruedLateFee = lateFeeDecimal(summary.cuotas[0]?.mora ?? 0);
  const paidLateFee = relatedPayments.reduce(
    (total, payment) => total.plus(payment.lateFeeApplied ?? 0),
    lateFeeDecimal(0),
  );
  return roundCurrency(
    Math.max(accruedLateFee.minus(paidLateFee).toNumber(), 0),
  );
}

export function resolveInstallmentsToProcess(input: {
  installments: LoadedInstallment[];
  paymentDate: Date;
  paymentTypeOverride: string;
  targetInstallmentId?: string | null;
  targetInstallmentNumber?: number | null;
  advanceInstallmentCount?: number | null;
}) {
  if (input.paymentTypeOverride === "abono_capital") {
    return [];
  }
  const isEligible = (installment: LoadedInstallment) =>
    !isClosedStatus(installment.status ?? "") &&
    remainingAmount(installment) > 0.009;

  if (input.targetInstallmentId) {
    const target = input.installments.find(
      (item) => item.id === input.targetInstallmentId && isEligible(item),
    );
    if (target) {
      return [target];
    }
  }
  if (input.targetInstallmentNumber != null) {
    const target = input.installments.find(
      (item) =>
        item.installmentNumber === input.targetInstallmentNumber &&
        isEligible(item),
    );
    if (target) {
      return [target];
    }
  }
  if (input.paymentTypeOverride === "todas_cuotas_vencidas") {
    return input.installments.filter(
      (item) =>
        isEligible(item) &&
        isDueOnOrBeforeBusinessDate(item.dueDate, input.paymentDate),
    );
  }
  if (input.paymentTypeOverride === "cuotas_adelantadas") {
    const selected = input.installments
      .filter(isEligible)
      .sort((left, right) => {
        const byDate = dateKeyInTimeZone(
          left.dueDate ?? new Date(0),
          BUSINESS_TIMEZONE,
        ).localeCompare(
          dateKeyInTimeZone(right.dueDate ?? new Date(0), BUSINESS_TIMEZONE),
        );
        if (byDate !== 0) return byDate;
        return (left.installmentNumber ?? 0) - (right.installmentNumber ?? 0);
      });
    const count =
      input.advanceInstallmentCount != null && input.advanceInstallmentCount > 0
        ? input.advanceInstallmentCount
        : selected.length;
    return selected.slice(0, count);
  }
  const actionable = input.installments.find(
    (item) =>
      isEligible(item) &&
      isDueOnOrBeforeBusinessDate(item.dueDate, input.paymentDate),
  );
  return actionable
    ? [actionable]
    : input.installments
        .filter(isEligible)
        .sort((left, right) => {
          const byDate = dateKeyInTimeZone(
            left.dueDate ?? new Date(0),
            BUSINESS_TIMEZONE,
          ).localeCompare(
            dateKeyInTimeZone(right.dueDate ?? new Date(0), BUSINESS_TIMEZONE),
          );
          if (byDate !== 0) return byDate;
          return (left.installmentNumber ?? 0) - (right.installmentNumber ?? 0);
        })
        .slice(0, 1);
}

function calculateOutstandingPrincipal(installments: LoadedInstallment[]) {
  return roundCurrency(
    installments
      .filter((item) => !["ajustada", "cancelada"].includes(item.status ?? ""))
      .reduce(
        (sum, item) =>
          sum +
          Math.min(
            Math.max(
              toNumber(item.principalAmount) -
                toNumber(item.paidPrincipalAmount),
              0,
            ),
            toNumber(item.principalAmount),
          ),
        0,
      ),
  );
}

async function recalculateFutureInstallments(
  tx: TransactionClient,
  input: {
    installments: LoadedInstallment[];
    paymentDate: Date;
    currentInstallmentNumber: number;
    monthlyInterest: number;
    fixedInstallmentAmount: number;
    remainingPrincipalBalance: number;
    shouldRecalculate: boolean;
  },
) {
  if (!input.shouldRecalculate) {
    return;
  }
  const futureInstallments = input.installments.filter((installment) => {
    if (isClosedStatus(installment.status ?? "")) {
      return false;
    }
    if (input.remainingPrincipalBalance <= 0) {
      return true;
    }
    if (input.currentInstallmentNumber > 0) {
      return (
        (installment.installmentNumber ?? 0) > input.currentInstallmentNumber
      );
    }
    return isAfterBusinessDate(installment.dueDate, input.paymentDate);
  });
  if (futureInstallments.length === 0) {
    return;
  }
  if (input.remainingPrincipalBalance <= 0) {
    await tx.installment.updateMany({
      where: { id: { in: futureInstallments.map((item) => item.id) } },
      data: zeroAdjustedInstallmentData(),
    });
    return;
  }

  const schedule = buildInstallmentSchedule({
    saleDate: input.paymentDate,
    dueDates: futureInstallments.map(
      (item) => item.dueDate ?? input.paymentDate,
    ),
    financedBalance: input.remainingPrincipalBalance,
    monthlyInterest: input.monthlyInterest,
    installmentCount: futureInstallments.length,
    fixedPaymentAmount: input.fixedInstallmentAmount,
    statusAsOf: input.paymentDate,
    startingInstallmentNumber: futureInstallments[0].installmentNumber ?? 1,
  });

  for (let index = 0; index < futureInstallments.length; index += 1) {
    const installment = futureInstallments[index];
    const recalculated = schedule[index];
    await tx.installment.update({
      where: { id: installment.id },
      data: recalculated
        ? {
            openingBalance: decimal(recalculated.openingBalance),
            principalAmount: decimal(recalculated.principalAmount),
            interestAmount: decimal(recalculated.interestAmount),
            totalAmount: decimal(recalculated.totalAmount),
            paidAmount: decimal(0),
            paidPrincipalAmount: decimal(0),
            paidInterestAmount: decimal(0),
            endingBalance: decimal(recalculated.endingBalance),
            status: "pendiente",
            version: { increment: 1 },
          }
        : zeroAdjustedInstallmentData(),
    });
  }
}

function isDueOnOrBeforeBusinessDate(
  dueDate: Date | null | undefined,
  asOf: Date,
) {
  if (!dueDate) return false;
  return (
    dateKeyInTimeZone(dueDate, BUSINESS_TIMEZONE) <=
    dateKeyInTimeZone(asOf, BUSINESS_TIMEZONE)
  );
}

function isPastDueBusinessDate(dueDate: Date | null | undefined, asOf: Date) {
  if (!dueDate) return false;
  return (
    dateKeyInTimeZone(dueDate, BUSINESS_TIMEZONE) <
    dateKeyInTimeZone(asOf, BUSINESS_TIMEZONE)
  );
}

function isAfterBusinessDate(dueDate: Date | null | undefined, asOf: Date) {
  if (!dueDate) return false;
  return (
    dateKeyInTimeZone(dueDate, BUSINESS_TIMEZONE) >
    dateKeyInTimeZone(asOf, BUSINESS_TIMEZONE)
  );
}

async function regenerateInstallmentsForActivatedSale(
  tx: TransactionClient,
  sale: Awaited<ReturnType<typeof loadSale>>,
  input: {
    paymentDate: Date;
    newStatus: string;
    updatedFinancedBalance: number;
    monthlyInterest: number;
    installmentCount: number;
    saleDate: Date;
  },
) {
  await tx.installment.updateMany({
    where: { saleId: sale.id, deletedAt: null },
    data: { deletedAt: input.paymentDate, version: { increment: 1 } },
  });
  if (input.newStatus !== "activa") {
    return;
  }
  const generatedInstallments = buildInstallmentSchedule({
    saleDate: input.saleDate,
    financedBalance: input.updatedFinancedBalance,
    monthlyInterest: input.monthlyInterest,
    installmentCount: input.installmentCount,
    statusAsOf: input.paymentDate,
  });
  await tx.installment.createMany({
    data: generatedInstallments.map((installment) => ({
      companyId: sale.companyId,
      syncId: newSyncId("installment"),
      saleId: sale.id,
      saleSyncId: sale.syncId,
      installmentNumber: installment.installmentNumber,
      dueDate: installment.dueDate,
      openingBalance: decimal(installment.openingBalance),
      principalAmount: decimal(installment.principalAmount),
      interestAmount: decimal(installment.interestAmount),
      totalAmount: decimal(installment.totalAmount),
      paidAmount: decimal(0),
      paidPrincipalAmount: decimal(0),
      paidInterestAmount: decimal(0),
      endingBalance: decimal(installment.endingBalance),
      status: installment.status,
      raw: { authoritativeSource: "phase_1d" },
    })),
  });
}

async function reverseInitialPayment(
  tx: TransactionClient,
  sale: Prisma.SaleGetPayload<Record<string, never>> | null,
  amount: number,
  annulledAt: Date,
  isReservation: boolean,
) {
  if (!sale) {
    throw new AuthoritativeError(
      "SALE_NOT_FOUND",
      "La venta seleccionada no existe.",
      404,
    );
  }
  // Para apartados, `initialPaid` es 0 y el dinero vive en `reservationPaidAmount`;
  // por eso la reversion debe descontar de la reserva y no del inicial.
  const updatedInitialPaid = isReservation
    ? toNumber(sale.initialPaid)
    : roundCurrency(Math.max(toNumber(sale.initialPaid) - amount, 0));
  const updatedReservationPaid = isReservation
    ? roundCurrency(Math.max(toNumber(sale.reservationPaidAmount) - amount, 0))
    : toNumber(sale.reservationPaidAmount);
  const updatedInitialPending = calculatePendingInitialPayment({
    requiredInitialPayment: toNumber(sale.initialRequiredAmount),
    initialPaymentPaid: updatedInitialPaid,
  });
  const updatedFinancedBalance = calculateFinancedBalance({
    salePrice: toNumber(sale.total),
    downPaymentAmount: updatedInitialPaid,
  });
  const newStatus = resolveUpfrontSaleStatus({
    initialRequiredAmount: toNumber(sale.initialRequiredAmount),
    initialPaidAmount: updatedInitialPaid,
    financedBalance: updatedFinancedBalance,
  });
  const updatedSale = await tx.sale.update({
    where: { id: sale.id },
    data: {
      initialPaid: decimal(updatedInitialPaid),
      reservationPaidAmount: decimal(updatedReservationPaid),
      initialPendingAmount: decimal(updatedInitialPending),
      financedBalance: decimal(updatedFinancedBalance),
      balance: decimal(updatedFinancedBalance),
      status: newStatus,
      activationDate:
        newStatus === "activa" || newStatus === "pagada"
          ? (sale.activationDate ?? annulledAt)
          : null,
      version: { increment: 1 },
    },
    select: { id: true, status: true, balance: true },
  });
  await tx.installment.updateMany({
    where: { saleId: sale.id, deletedAt: null },
    data: { deletedAt: annulledAt, version: { increment: 1 } },
  });
  if (sale.lotId) {
    await tx.lot.update({
      where: { id: sale.lotId },
      data: {
        status:
          newStatus === "activa" || newStatus === "pagada"
            ? "vendido"
            : "reservado",
        version: { increment: 1 },
      },
    });
  }
  return updatedSale;
}

async function reverseCapitalPayment(
  tx: TransactionClient,
  sale: Prisma.SaleGetPayload<Record<string, never>> | null,
  amount: number,
  annulledAt: Date,
) {
  if (!sale) {
    return;
  }
  const installments = await loadActiveInstallments(tx, sale.id);
  const activeFuture = installments.filter(
    (item) => !isClosedStatus(item.status ?? ""),
  );
  if (activeFuture.length === 0) {
    await tx.sale.update({
      where: { id: sale.id },
      data: {
        balance: decimal(roundCurrency(toNumber(sale.balance) + amount)),
        status: "activa",
        version: { increment: 1 },
      },
    });
    return;
  }
  const restoredBalance = roundCurrency(
    calculateOutstandingPrincipal(installments) + amount,
  );
  await recalculateFutureInstallments(tx, {
    installments,
    paymentDate: annulledAt,
    currentInstallmentNumber: 0,
    monthlyInterest: toNumber(sale.monthlyInterestRate),
    fixedInstallmentAmount: calculateEstimatedInstallmentAmount({
      financedBalance: toNumber(sale.financedBalance),
      monthlyInterest: toNumber(sale.monthlyInterestRate),
      installmentCount: sale.installmentCount ?? activeFuture.length,
    }),
    remainingPrincipalBalance: restoredBalance,
    shouldRecalculate: true,
  });
}

async function hasOpenInstallmentBalance(
  tx: TransactionClient,
  saleId: string,
) {
  const installments = await loadActiveInstallments(tx, saleId);
  return installments.some(
    (item) =>
      !["pagada", "ajustada", "cancelada"].includes(item.status ?? "") &&
      remainingAmount(item) > 0.009,
  );
}

async function loadOutstandingContractBalance(
  tx: TransactionClient,
  saleId: string,
) {
  const installments = await loadActiveInstallments(tx, saleId);
  return calculateOutstandingPrincipal(installments);
}

function remainingAmount(
  installment: Pick<LoadedInstallment, "totalAmount" | "paidAmount">,
) {
  return roundCurrency(
    Math.max(
      toNumber(installment.totalAmount) - toNumber(installment.paidAmount),
      0,
    ),
  );
}

function isClosedStatus(status: string) {
  return status === "pagada" || status === "ajustada" || status === "cancelada";
}

function paymentReference(
  input: Pick<RegisterAuthoritativePaymentInput, "reference">,
  saleId: string,
  now: Date,
) {
  return input.reference ?? `PAY-${saleId}-${now.getTime().toString()}`;
}

function zeroAdjustedInstallmentData(): Prisma.InstallmentUpdateInput {
  return {
    openingBalance: decimal(0),
    principalAmount: decimal(0),
    interestAmount: decimal(0),
    totalAmount: decimal(0),
    paidAmount: decimal(0),
    paidPrincipalAmount: decimal(0),
    paidInterestAmount: decimal(0),
    endingBalance: decimal(0),
    status: "ajustada",
    version: { increment: 1 },
  };
}
