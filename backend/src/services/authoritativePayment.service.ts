import { Prisma, PrismaClient } from '@prisma/client';
import { AuthoritativeError } from './authoritativeErrors.service';
import {
  buildInstallmentSchedule,
  calculateEstimatedInstallmentAmount,
  calculateFinancedBalance,
  calculatePendingInitialPayment,
  resolveInstallmentStatus,
  resolveUpfrontSaleStatus,
  roundCurrency,
} from './financing.service';
import {
  decimal,
  newSyncId,
  normalizePaymentMethod,
  parseDate,
  toNumber,
} from './authoritativeSale.service';
import {
  IdempotentResult,
  requireIdempotencyKey,
  runIdempotentOperation,
} from './idempotency.service';

type TransactionClient = Prisma.TransactionClient;
type LoadedInstallment = Awaited<ReturnType<typeof loadActiveInstallments>>[number];

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
  yearToPay?: number | null;
  reference?: string | null;
  quoteVersion?: string | null;
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

  async getSettlementQuote(input: SettlementQuoteInput): Promise<Prisma.JsonObject> {
    return this.prisma.$transaction(async (tx) => {
      const sale = await loadSale(tx, {
        companyId: input.companyId,
        receivedByUserId: '',
        idempotencyKey: 'quote',
        saleId: input.saleId,
      });
      const installments = await loadActiveInstallments(tx, sale.id);
      return buildSettlementQuoteResponse(sale, installments, parseDate(input.asOfDate, new Date()));
    });
  }

  async registerPayment(
    input: RegisterAuthoritativePaymentInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: 'payment.register',
        requestPayload: input,
        run: async () => {
          const response = await registerPaymentInTransaction(tx, input);
          return {
            response,
            resourceType: 'payment',
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
        operationType: 'payment.annul',
        requestPayload: input,
        run: async () => {
          const response = await annulPaymentInTransaction(tx, input);
          return {
            response,
            resourceType: 'payment',
            resourceId: input.paymentId,
          };
        },
      }),
    );
  }

  async settleSale(input: SettleSaleInput): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: 'payment.settlement',
        requestPayload: input,
        run: async () => {
          const response = await settleSaleInTransaction(tx, input);
          return {
            response,
            resourceType: 'payment',
            resourceId: String(response.paymentId),
          };
        },
      }),
    );
  }
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
  if ((sale.status ?? '') === 'cancelada' || sale.deletedAt) {
    throw new AuthoritativeError('SALE_STATUS_REJECTED', 'La venta seleccionada no admite liquidacion.');
  }
  if (toNumber(sale.initialPendingAmount) > 0.009) {
    throw new AuthoritativeError(
      'INITIAL_PENDING_BLOCKS_SETTLEMENT',
      'Completa primero el inicial pendiente antes de saldar la deuda total.',
      409,
    );
  }

  const installments = await loadActiveInstallments(tx, sale.id);
  const quote = buildSettlementQuoteResponse(sale, installments, paymentDate);
  if (quote.settlementAmount <= 0.009 || quote.isFullyPaid === true) {
    throw new AuthoritativeError('SALE_ALREADY_PAID', 'La venta seleccionada ya esta saldada.', 409);
  }
  if (input.quoteVersion && input.quoteVersion !== quote.quoteVersion) {
    throw new AuthoritativeError(
      'STALE_SETTLEMENT_QUOTE',
      'El saldo cambio. Revisa el monto actualizado antes de continuar.',
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
    if (isClosedStatus(installment.status ?? '')) {
      continue;
    }
    const due = (installment.dueDate?.getTime() ?? Number.POSITIVE_INFINITY) <= paymentDate.getTime();
    if (due) {
      await tx.installment.update({
        where: { id: installment.id },
        data: {
          paidAmount: installment.totalAmount,
          paidPrincipalAmount: installment.principalAmount,
          paidInterestAmount: installment.interestAmount,
          status: 'pagada',
          raw: mergeRaw(installment.raw, { settlementReason: 'liquidacion_total' }),
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
          status: 'ajustada',
          raw: mergeRaw(installment.raw, { adjustmentReason: 'liquidacion_total' }),
          version: { increment: 1 },
        },
      });
    }
  }

  const payment = await tx.payment.create({
    data: {
      companyId: input.companyId,
      syncId: newSyncId('payment'),
      saleId: sale.id,
      clientId: sale.clientId,
      receivedByUserId: input.receivedByUserId,
      saleSyncId: sale.syncId,
      clientSyncId: sale.clientSyncId,
      paidAt: paymentDate,
      amount: decimal(quote.settlementAmount),
      method: normalizePaymentMethod(input.paymentMethod),
      paymentType: 'liquidacion_total',
      reference: input.reference ?? `SETTLEMENT-${sale.id}-${now.getTime().toString()}`,
      principalApplied: decimal(quote.principalOutstanding),
      interestApplied: decimal(quote.dueInterest),
      raw: {
        authoritativeSource: 'settlement',
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
      status: 'pagada',
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
      data: { status: 'vendido', version: { increment: 1 } },
    });
  }

  return {
    saleId: sale.id,
    paymentId: payment.id,
    status: 'pagada',
    balance: 0,
    initialPendingAmount: 0,
    paymentType: 'liquidacion_total',
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
    throw new AuthoritativeError('INVALID_PAYMENT_AMOUNT', 'El monto pagado debe ser mayor que cero.');
  }

  const sale = await loadSale(tx, input);
  const saleStatus = sale.status ?? 'apartado';
  const paymentTypeOverride =
    input.paymentTypeOverride ?? input.paymentType ?? 'cuota';
  const pendingInitial = toNumber(sale.initialPendingAmount);
  const pendingBalance = toNumber(sale.balance);
  const salePrice = toNumber(sale.total);
  const paidInitial = toNumber(sale.initialPaid);
  const requiredInitial = toNumber(sale.initialRequiredAmount);
  const monthlyInterest = toNumber(sale.monthlyInterestRate);
  const installmentCount = sale.installmentCount ?? 0;
  const saleDate = sale.saleDate ?? paymentDate;
  const paymentIds: string[] = [];

  if (pendingInitial <= 0.009 && pendingBalance <= 0.009) {
    throw new AuthoritativeError(
      'SALE_ALREADY_PAID',
      'La venta seleccionada ya no tiene saldo pendiente.',
      409,
    );
  }

  if (paymentTypeOverride === 'abono_capital') {
    await assertCapitalPaymentAllowed(tx, sale.id, pendingInitial, paymentDate);
  }

  if (saleStatus === 'apartado' || saleStatus === 'inicial_incompleto') {
    const saleAmountRemaining = roundCurrency(Math.max(salePrice - paidInitial, 0));
    const initialPaymentApplied = Math.min(amountPaid, saleAmountRemaining);
    if (initialPaymentApplied <= 0) {
      throw new AuthoritativeError('NO_PAYMENT_IMPACT', 'El pago no impacto la venta seleccionada.');
    }

    const updatedInitialPaid = roundCurrency(paidInitial + initialPaymentApplied);
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
        syncId: newSyncId('payment'),
        saleId: sale.id,
        clientId: sale.clientId,
        receivedByUserId: input.receivedByUserId,
        saleSyncId: sale.syncId,
        clientSyncId: sale.clientSyncId,
        paidAt: paymentDate,
        amount: decimal(initialPaymentApplied),
        method: normalizePaymentMethod(input.paymentMethod),
        paymentType: paidInitial <= 0.009 ? 'apartado' : 'abono_inicial',
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(0),
        interestApplied: decimal(0),
        raw: { authoritativeSource: 'phase_1d' },
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
          newStatus === 'activa' || newStatus === 'pagada' ? paymentDate : null,
        version: { increment: 1 },
      },
    });

    if (sale.lotId) {
      await tx.lot.update({
        where: { id: sale.lotId },
        data: {
          status: newStatus === 'activa' || newStatus === 'pagada' ? 'vendido' : 'reservado',
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
        'PAYMENT_EXCEEDS_BALANCE',
        'El pago excede el monto restante de la venta.',
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

  if (saleStatus !== 'activa' && saleStatus !== 'pagada') {
    throw new AuthoritativeError(
      'SALE_STATUS_REJECTED',
      'La venta seleccionada no admite pagos en su estado actual.',
    );
  }
  if (pendingBalance <= 0.009) {
    throw new AuthoritativeError(
      'SALE_PLAN_PAID',
      'La venta seleccionada ya no tiene saldo pendiente del plan.',
      409,
    );
  }

  const installments = await loadActiveInstallments(tx, sale.id);
  const outstandingPrincipal = calculateOutstandingPrincipal(installments);
  const fixedInstallmentAmount = calculateEstimatedInstallmentAmount({
    financedBalance: toNumber(sale.financedBalance),
    monthlyInterest,
    installmentCount,
  });
  const installmentsToProcess = resolveInstallmentsToProcess({
    installments,
    paymentDate,
    paymentTypeOverride,
    targetInstallmentId: input.targetInstallmentId ?? null,
    targetInstallmentNumber: input.targetInstallmentNumber ?? null,
  });
  const requiresInstallmentImpact = [
    'cuota',
    'cuota_vencida',
    'todas_cuotas_vencidas',
  ].includes(paymentTypeOverride);
  const openInstallmentIds = new Set(
    installments
      .filter((item) => !isClosedStatus(item.status ?? '') && remainingAmount(item) > 0.009)
      .map((item) => item.id),
  );
  const selectedInstallmentIds = new Set(installmentsToProcess.map((item) => item.id));

  let remaining = amountPaid;
  let totalPrincipalReduction = 0;
  let currentInstallmentNumber = 0;
  let installmentAppliedTotal = 0;

  for (const installment of installmentsToProcess) {
    if (remaining <= 0.009) {
      break;
    }
    currentInstallmentNumber = installment.installmentNumber ?? 0;
    const outcome = applyToInstallment(installment, remaining, paymentDate);
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
        syncId: newSyncId('payment'),
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
        paymentType: 'cuota',
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(outcome.principalPaidNow),
        interestApplied: decimal(outcome.interestPaidNow),
        raw: { authoritativeSource: 'phase_1d' },
      },
      select: { id: true },
    });
    paymentIds.push(payment.id);

    remaining = outcome.remainingAmount;
    installmentAppliedTotal = roundCurrency(installmentAppliedTotal + outcome.appliedAmount);
    totalPrincipalReduction = roundCurrency(
      totalPrincipalReduction + outcome.principalPaidNow,
    );
  }

  if (requiresInstallmentImpact && installmentAppliedTotal <= 0.009) {
    throw new AuthoritativeError(
      'NO_INSTALLMENT_IMPACT',
      'El pago no impacto ninguna cuota elegible.',
    );
  }

  let capitalPrepayment = 0;
  if (remaining > 0.009) {
    const maxCapitalPayment = roundCurrency(outstandingPrincipal - totalPrincipalReduction);
    if (maxCapitalPayment <= 0) {
      throw new AuthoritativeError(
        'PAYMENT_EXCEEDS_BALANCE',
        'El pago excede el saldo pendiente disponible.',
      );
    }
    capitalPrepayment = Math.min(remaining, maxCapitalPayment);
    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId('payment'),
        saleId: sale.id,
        clientId: sale.clientId,
        receivedByUserId: input.receivedByUserId,
        saleSyncId: sale.syncId,
        clientSyncId: sale.clientSyncId,
        paidAt: paymentDate,
        amount: decimal(capitalPrepayment),
        method: normalizePaymentMethod(input.paymentMethod),
        paymentType: 'abono_capital',
        reference: paymentReference(input, sale.id, now),
        yearToPay: input.yearToPay,
        principalApplied: decimal(capitalPrepayment),
        interestApplied: decimal(0),
        raw: { authoritativeSource: 'phase_1d' },
      },
      select: { id: true },
    });
    paymentIds.push(payment.id);
    remaining = roundCurrency(remaining - capitalPrepayment);
    totalPrincipalReduction = roundCurrency(totalPrincipalReduction + capitalPrepayment);
  }

  if (remaining > 0.009) {
    throw new AuthoritativeError(
      'PAYMENT_EXCEEDS_BALANCE',
      'El pago excede el saldo pendiente de la venta.',
    );
  }

  const settlesDisplayedBalance =
    paymentTypeOverride === 'abono_capital' && amountPaid >= pendingBalance - 0.009;
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
      if (['pagada', 'ajustada', 'cancelada'].includes(installment.status ?? '')) {
        continue;
      }
      await tx.installment.update({
        where: { id: installment.id },
        data: {
          paidAmount: installment.totalAmount,
          paidPrincipalAmount: installment.principalAmount,
          paidInterestAmount: installment.interestAmount,
          status: 'pagada',
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
  const newStatus = newPendingBalance <= 0.009 ? 'pagada' : 'activa';

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
function mergeAnnulmentAudit(raw: unknown, audit: Record<string, unknown>): Prisma.InputJsonValue {
  const base =
    raw && typeof raw === 'object' && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  base.annulmentAudit = audit;
  return base as Prisma.InputJsonValue;
}

async function annulPaymentInTransaction(
  tx: TransactionClient,
  input: AnnulAuthoritativePaymentInput,
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
    throw new AuthoritativeError('PAYMENT_NOT_FOUND', 'El pago seleccionado no existe.', 404);
  }
  if (payment.annulledAt) {
    // Idempotencia de anulacion: nunca reversar dos veces el mismo pago.
    throw new AuthoritativeError('PAYMENT_ALREADY_ANNULLED', 'Este pago ya fue anulado.', 409);
  }
  if (payment.deletedAt) {
    throw new AuthoritativeError('PAYMENT_NOT_FOUND', 'El pago seleccionado no existe.', 404);
  }

  const latest = await tx.payment.findFirst({
    where: {
      companyId: input.companyId,
      saleId: payment.saleId,
      deletedAt: null,
      annulledAt: null,
    },
    orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }, { id: 'desc' }],
    select: { id: true },
  });
  if (latest?.id !== payment.id) {
    throw new AuthoritativeError(
      'ONLY_LATEST_PAYMENT_CAN_BE_ANNULLED',
      'Solo se permite anular el ultimo pago activo de la venta.',
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
    const newPaidAmount = roundCurrency(Math.max(toNumber(installment.paidAmount) - amount, 0));
    const newPrincipalPaid = roundCurrency(
      Math.max(toNumber(installment.paidPrincipalAmount) - toNumber(payment.principalApplied), 0),
    );
    const newInterestPaid = roundCurrency(
      Math.max(toNumber(installment.paidInterestAmount) - toNumber(payment.interestApplied), 0),
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

  if (payment.paymentType === 'apartado' || payment.paymentType === 'abono_inicial') {
    const updatedSale = await reverseInitialPayment(
      tx,
      payment.sale,
      amount,
      annulledAt,
      payment.paymentType === 'apartado',
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
  } else if (payment.paymentType === 'liquidacion_total') {
    await restoreSettlementPreSnapshot(tx, payment);
    return {
      paymentId: payment.id,
      saleId: payment.sale.id,
      status: snapshotSaleStatus(payment.raw) ?? 'activa',
      balance: snapshotSaleBalance(payment.raw),
      annulledAt: annulledAt.toISOString(),
      performedByUserId: input.annulledByUserId,
      authorizedByUserId,
    };
  } else if (payment.paymentType === 'abono_capital') {
    await reverseCapitalPayment(tx, payment.sale, amount, annulledAt);
  }

  const newBalance = await loadOutstandingContractBalance(tx, payment.sale.id);
  const updatedSale = await tx.sale.update({
    where: { id: payment.sale.id },
    data: {
      balance: decimal(newBalance),
      status: newBalance <= 0.009 && toNumber(payment.sale.initialPendingAmount) <= 0.009
        ? 'pagada'
        : payment.sale.status === 'pagada'
          ? 'activa'
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

function buildSettlementQuoteResponse(
  sale: Awaited<ReturnType<typeof loadSale>>,
  installments: LoadedInstallment[],
  asOfDate: Date,
) {
  const open = installments.filter((item) => !isClosedStatus(item.status ?? ''));
  const principalOutstanding = roundCurrency(
    open.reduce(
      (sum, item) =>
        sum + Math.max(toNumber(item.principalAmount) - toNumber(item.paidPrincipalAmount), 0),
      0,
    ),
  );
  const dueInterest = roundCurrency(
    open
      .filter((item) => (item.dueDate?.getTime() ?? Number.POSITIVE_INFINITY) <= asOfDate.getTime())
      .reduce(
        (sum, item) =>
          sum + Math.max(toNumber(item.interestAmount) - toNumber(item.paidInterestAmount), 0),
        0,
      ),
  );
  const futureInterestWaived = roundCurrency(
    open
      .filter((item) => (item.dueDate?.getTime() ?? Number.POSITIVE_INFINITY) > asOfDate.getTime())
      .reduce(
        (sum, item) =>
          sum + Math.max(toNumber(item.interestAmount) - toNumber(item.paidInterestAmount), 0),
        0,
      ),
  );
  const settlementAmount = roundCurrency(principalOutstanding + dueInterest);
  const lateFees = 0;
  const fingerprint = [
    sale.id,
    sale.version,
    toNumber(sale.balance).toFixed(2),
    toNumber(sale.initialPendingAmount).toFixed(2),
    ...installments.map((item) =>
      [
        item.id,
        item.version,
        item.status ?? '',
        toNumber(item.principalAmount).toFixed(2),
        toNumber(item.interestAmount).toFixed(2),
        toNumber(item.paidPrincipalAmount).toFixed(2),
        toNumber(item.paidInterestAmount).toFixed(2),
        toNumber(item.paidAmount).toFixed(2),
      ].join(':'),
    ),
  ].join('|');
  return {
    saleId: sale.id,
    asOfDate: asOfDate.toISOString(),
    principalOutstanding,
    dueInterest,
    lateFees,
    futureInterestWaived,
    settlementAmount,
    quoteVersion: Buffer.from(fingerprint).toString('base64url'),
    isFullyPaid:
      toNumber(sale.initialPendingAmount) <= 0.009 &&
      settlementAmount <= 0.009 &&
      (sale.status ?? '') === 'pagada',
  };
}

export function buildSettlementQuoteForTest(input: {
  sale: Awaited<ReturnType<typeof loadSale>>;
  installments: LoadedInstallment[];
  asOfDate: Date;
}) {
  return buildSettlementQuoteResponse(input.sale, input.installments, input.asOfDate);
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
  payment: Prisma.PaymentGetPayload<{ include: { sale: true; installment: true } }>,
) {
  const snapshot = readSettlementSnapshot(payment.raw);
  if (!snapshot?.sale) {
    throw new AuthoritativeError(
      'SETTLEMENT_SNAPSHOT_MISSING',
      'No se encontro el snapshot financiero para anular esta liquidacion.',
      409,
    );
  }
  await tx.sale.update({
    where: { id: String(snapshot.sale.id) },
    data: {
      status: stringOrNull(snapshot.sale.status) ?? 'activa',
      balance: decimal(toNumber(snapshot.sale.balance)),
      initialPendingAmount: decimal(toNumber(snapshot.sale.initialPendingAmount)),
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
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }
  const snapshot = (raw as Record<string, unknown>).preSnapshot;
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
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
  return lot && typeof lot === 'object' && !Array.isArray(lot) ? lot : null;
}

function snapshotSaleStatus(raw: unknown) {
  return stringOrNull(readSettlementSnapshot(raw)?.sale?.status);
}

function snapshotSaleBalance(raw: unknown) {
  return toNumber(readSettlementSnapshot(raw)?.sale?.balance);
}

function mergeRaw(raw: unknown, patch: Record<string, unknown>): Prisma.InputJsonValue {
  const base =
    raw && typeof raw === 'object' && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  return { ...base, ...patch } as Prisma.InputJsonValue;
}

function stringOrNull(value: unknown) {
  return typeof value === 'string' ? value : null;
}

async function loadSale(tx: TransactionClient, input: RegisterAuthoritativePaymentInput) {
  const sale = input.saleId
    ? await tx.sale.findFirst({
        where: { id: input.saleId, companyId: input.companyId, deletedAt: null },
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
    throw new AuthoritativeError('SALE_NOT_FOUND', 'La venta seleccionada no existe.', 404);
  }
  return sale;
}

async function loadActiveInstallments(tx: TransactionClient, saleId: string) {
  return tx.installment.findMany({
    where: { saleId, deletedAt: null },
    orderBy: { installmentNumber: 'asc' },
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
      'CAPITAL_PAYMENT_BLOCKED_INITIAL_PENDING',
      'No puedes aplicar pago a capital porque este cliente tiene un inicial pendiente. Primero debes completar el pago inicial.',
      409,
    );
  }
  const overdue = await tx.installment.findFirst({
    where: {
      saleId,
      deletedAt: null,
      status: { notIn: ['pagada', 'ajustada', 'cancelada'] },
      dueDate: { lt: paymentDate },
    },
  });
  if (overdue && remainingAmount(overdue) > 0.009) {
    throw new AuthoritativeError(
      'CAPITAL_PAYMENT_BLOCKED_OVERDUE_INSTALLMENTS',
      'No puedes aplicar pago a capital porque este cliente tiene cuotas vencidas. Primero debes saldar las cuotas atrasadas.',
      409,
    );
  }
}

export function applyToInstallment(installment: LoadedInstallment, amount: number, asOf: Date) {
  const installmentRemaining = remainingAmount(installment);
  const appliedAmount = amount > installmentRemaining ? installmentRemaining : amount;
  const interestRemaining = toNumber(installment.interestAmount) - toNumber(installment.paidInterestAmount);
  const interestPaidNow = appliedAmount > interestRemaining ? interestRemaining : appliedAmount;
  const principalPaidNow = roundCurrency(appliedAmount - interestPaidNow);
  const newPaidAmount = roundCurrency(toNumber(installment.paidAmount) + appliedAmount);
  const newInterestPaid = roundCurrency(toNumber(installment.paidInterestAmount) + interestPaidNow);
  const newPrincipalPaid = roundCurrency(toNumber(installment.paidPrincipalAmount) + principalPaidNow);

  return {
    appliedAmount: roundCurrency(appliedAmount),
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

export function resolveInstallmentsToProcess(input: {
  installments: LoadedInstallment[];
  paymentDate: Date;
  paymentTypeOverride: string;
  targetInstallmentId?: string | null;
  targetInstallmentNumber?: number | null;
}) {
  if (input.paymentTypeOverride === 'abono_capital') {
    return [];
  }
  const isEligible = (installment: LoadedInstallment) =>
    !isClosedStatus(installment.status ?? '') && remainingAmount(installment) > 0.009;

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
        item.installmentNumber === input.targetInstallmentNumber && isEligible(item),
    );
    if (target) {
      return [target];
    }
  }
  if (input.paymentTypeOverride === 'todas_cuotas_vencidas') {
    return input.installments.filter(
      (item) =>
        isEligible(item) &&
        (item.dueDate?.getTime() ?? Number.POSITIVE_INFINITY) <= input.paymentDate.getTime(),
    );
  }
  const actionable = input.installments.find(
    (item) =>
      isEligible(item) &&
      (item.dueDate?.getTime() ?? Number.POSITIVE_INFINITY) <= input.paymentDate.getTime(),
  );
  return actionable ? [actionable] : input.installments.filter(isEligible).slice(0, 1);
}

function calculateOutstandingPrincipal(installments: LoadedInstallment[]) {
  return roundCurrency(
    installments
      .filter((item) => !['ajustada', 'cancelada'].includes(item.status ?? ''))
      .reduce(
        (sum, item) =>
          sum +
          Math.min(
            Math.max(toNumber(item.principalAmount) - toNumber(item.paidPrincipalAmount), 0),
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
    if (isClosedStatus(installment.status ?? '')) {
      return false;
    }
    if (input.remainingPrincipalBalance <= 0) {
      return true;
    }
    if (input.currentInstallmentNumber > 0) {
      return (installment.installmentNumber ?? 0) > input.currentInstallmentNumber;
    }
    return (installment.dueDate?.getTime() ?? 0) > input.paymentDate.getTime();
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
    dueDates: futureInstallments.map((item) => item.dueDate ?? input.paymentDate),
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
            status: 'pendiente',
            version: { increment: 1 },
          }
        : zeroAdjustedInstallmentData(),
    });
  }
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
  if (input.newStatus !== 'activa') {
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
      syncId: newSyncId('installment'),
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
      raw: { authoritativeSource: 'phase_1d' },
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
    throw new AuthoritativeError('SALE_NOT_FOUND', 'La venta seleccionada no existe.', 404);
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
      activationDate: newStatus === 'activa' || newStatus === 'pagada'
        ? sale.activationDate ?? annulledAt
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
        status: newStatus === 'activa' || newStatus === 'pagada' ? 'vendido' : 'reservado',
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
  const activeFuture = installments.filter((item) => !isClosedStatus(item.status ?? ''));
  if (activeFuture.length === 0) {
    await tx.sale.update({
      where: { id: sale.id },
      data: {
        balance: decimal(roundCurrency(toNumber(sale.balance) + amount)),
        status: 'activa',
        version: { increment: 1 },
      },
    });
    return;
  }
  const restoredBalance = roundCurrency(calculateOutstandingPrincipal(installments) + amount);
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

async function hasOpenInstallmentBalance(tx: TransactionClient, saleId: string) {
  const installments = await loadActiveInstallments(tx, saleId);
  return installments.some(
    (item) => !['pagada', 'ajustada', 'cancelada'].includes(item.status ?? '') && remainingAmount(item) > 0.009,
  );
}

async function loadOutstandingContractBalance(tx: TransactionClient, saleId: string) {
  const installments = await loadActiveInstallments(tx, saleId);
  return calculateOutstandingPrincipal(installments);
}

function remainingAmount(installment: Pick<LoadedInstallment, 'totalAmount' | 'paidAmount'>) {
  return roundCurrency(
    Math.max(toNumber(installment.totalAmount) - toNumber(installment.paidAmount), 0),
  );
}

function isClosedStatus(status: string) {
  return status === 'pagada' || status === 'ajustada' || status === 'cancelada';
}

function paymentReference(
  input: Pick<RegisterAuthoritativePaymentInput, 'reference'>,
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
    status: 'ajustada',
    version: { increment: 1 },
  };
}
