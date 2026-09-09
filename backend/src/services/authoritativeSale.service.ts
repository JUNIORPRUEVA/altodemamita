import { randomUUID } from 'crypto';
import { Prisma, PrismaClient } from '@prisma/client';
import {
  buildInstallmentSchedule,
  calculateDownPaymentAmount,
  calculateFinancedBalance,
  calculatePendingInitialPayment,
  resolveSaleStatus,
  roundCurrency,
} from './financing.service';
import { AuthoritativeError } from './authoritativeErrors.service';
import {
  IdempotentResult,
  requireIdempotencyKey,
  runIdempotentOperation,
} from './idempotency.service';

type TransactionClient = Prisma.TransactionClient;

export type CreateAuthoritativeSaleInput = {
  companyId: string;
  operatorUserId: string;
  idempotencyKey: string;
  clientId?: string;
  clientSyncId?: string;
  lotId?: string;
  lotSyncId?: string;
  sellerId?: string | null;
  sellerSyncId?: string | null;
  syncId?: string;
  saleDate?: string | Date;
  salePrice?: number;
  downPaymentPercentage?: number;
  initialPercentage?: number;
  requiredInitialPayment?: number;
  initialPaymentPaid?: number;
  initialIsApartado?: boolean;
  minimumReserveAmount?: number | null;
  initialPaymentDeadline?: string | Date | null;
  monthlyInterest?: number;
  installmentCount?: number;
  initialPaymentMethod?: string | null;
  reference?: string | null;
};

export type CancelAuthoritativeSaleInput = {
  companyId: string;
  cancelledByUserId: string;
  idempotencyKey: string;
  saleId: string;
  reason?: string | null;
  cancelledAt?: string | Date;
};

export class AuthoritativeSaleService {
  constructor(private readonly prisma: PrismaClient) {}

  async createSale(
    input: CreateAuthoritativeSaleInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: 'sale.create',
        requestPayload: input,
        run: async () => {
          const response = await createSaleInTransaction(tx, input);
          return {
            response,
            resourceType: 'sale',
            resourceId: String(response.saleId),
          };
        },
      }),
    );
  }

  async cancelSale(
    input: CancelAuthoritativeSaleInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: 'sale.cancel',
        requestPayload: input,
        run: async () => {
          const response = await cancelSaleInTransaction(tx, input);
          return {
            response,
            resourceType: 'sale',
            resourceId: input.saleId,
          };
        },
      }),
    );
  }
}

async function createSaleInTransaction(
  tx: TransactionClient,
  input: CreateAuthoritativeSaleInput,
): Promise<Prisma.JsonObject> {
  const now = new Date();
  const saleDate = parseDate(input.saleDate, now);
  const defaults = await tx.financialParameters.findUnique({
    where: { companyId: input.companyId },
  });
  const downPaymentPercentage =
    input.downPaymentPercentage ??
    input.initialPercentage ??
    toNumber(defaults?.initialPercentage);
  const monthlyInterest = input.monthlyInterest ?? toNumber(defaults?.monthlyInterestRate);
  const installmentCount = input.installmentCount ?? defaults?.installmentCount ?? 0;

  if (downPaymentPercentage < 0 || downPaymentPercentage > 100) {
    throw new AuthoritativeError(
      'INVALID_INITIAL_PERCENTAGE',
      'El porcentaje de inicial debe estar entre 0% y 100%.',
    );
  }
  if (monthlyInterest < 0) {
    throw new AuthoritativeError(
      'INVALID_MONTHLY_INTEREST',
      'El interes mensual no puede ser negativo.',
    );
  }
  if (installmentCount <= 0) {
    throw new AuthoritativeError(
      'INVALID_INSTALLMENT_COUNT',
      'La venta debe generar al menos una cuota.',
    );
  }

  const client = await findActiveClient(tx, input);
  const lot = await findActiveLot(tx, input);
  const seller = await findActiveSeller(tx, input);

  if (lot.status && !['disponible'].includes(lot.status)) {
    throw new AuthoritativeError(
      'LOT_NOT_AVAILABLE',
      'El solar seleccionado no esta disponible.',
      409,
    );
  }

  const existingActiveSale = await tx.sale.findFirst({
    where: {
      companyId: input.companyId,
      lotId: lot.id,
      deletedAt: null,
      NOT: { status: 'cancelada' },
    },
    select: { id: true },
  });
  if (existingActiveSale) {
    throw new AuthoritativeError(
      'LOT_ALREADY_SOLD',
      'Ya existe una venta registrada para este solar.',
      409,
    );
  }

  const salePrice =
    input.salePrice && input.salePrice > 0
      ? roundCurrency(input.salePrice)
      : roundCurrency(toNumber(lot.area) * toNumber(lot.price));
  if (salePrice <= 0) {
    throw new AuthoritativeError(
      'INVALID_LOT_PRICE',
      'El solar seleccionado no tiene un precio total valido para registrar la venta.',
    );
  }

  const requiredInitial = roundCurrency(
    input.requiredInitialPayment ??
      calculateDownPaymentAmount({
        salePrice,
        downPaymentPercentage,
      }),
  );
  const providedAmount = roundCurrency(input.initialPaymentPaid ?? 0);
  const initialPaid = input.initialIsApartado ? 0 : providedAmount;
  const reservationPaid = input.initialIsApartado ? providedAmount : 0;
  const minimumReserveAmount =
    input.minimumReserveAmount == null ? 0 : roundCurrency(input.minimumReserveAmount);

  if (initialPaid < 0 || reservationPaid < 0) {
    throw new AuthoritativeError(
      'INVALID_INITIAL_PAYMENT',
      'El inicial pagado no puede ser negativo.',
    );
  }
  if (minimumReserveAmount < 0) {
    throw new AuthoritativeError(
      'INVALID_RESERVATION_MINIMUM',
      'El monto minimo de apartado no puede ser negativo.',
    );
  }
  if (minimumReserveAmount - requiredInitial > 0.009) {
    throw new AuthoritativeError(
      'INVALID_RESERVATION_MINIMUM',
      'El monto minimo de apartado no puede exceder el inicial requerido.',
    );
  }
  if (initialPaid + 0.009 < requiredInitial && !input.initialPaymentDeadline) {
    throw new AuthoritativeError(
      'INITIAL_DEADLINE_REQUIRED',
      'El inicial pagado es menor al requerido. Debes especificar una fecha limite para el completivo del inicial.',
    );
  }
  if (initialPaid - salePrice > 0.009) {
    throw new AuthoritativeError(
      'INITIAL_EXCEEDS_TOTAL',
      'El inicial pagado no puede exceder el precio total del solar.',
    );
  }

  const financedBalance = calculateFinancedBalance({
    salePrice,
    downPaymentAmount: initialPaid,
  });
  const initialPendingAmount = calculatePendingInitialPayment({
    requiredInitialPayment: requiredInitial,
    initialPaymentPaid: initialPaid,
  });
  const status = resolveSaleStatus({
    initialRequiredAmount: requiredInitial,
    initialPaidAmount: initialPaid,
    minimumReserveAmount,
    financedBalance,
  });

  const sale = await tx.sale.create({
    data: {
      companyId: input.companyId,
      syncId: input.syncId ?? newSyncId('sale'),
      clientId: client.id,
      lotId: lot.id,
      sellerId: seller?.id,
      operatorUserId: input.operatorUserId,
      clientSyncId: client.syncId,
      lotSyncId: lot.syncId,
      sellerSyncId: seller?.syncId,
      saleDate,
      status,
      total: decimal(salePrice),
      initialPercentage: decimal(downPaymentPercentage),
      initialRequiredAmount: decimal(requiredInitial),
      initialPaid: decimal(initialPaid),
      initialPendingAmount: decimal(initialPendingAmount),
      reservationMinimumAmount: decimal(minimumReserveAmount),
      reservationPaidAmount: decimal(reservationPaid),
      initialPaymentDeadline: input.initialPaymentDeadline
        ? parseDate(input.initialPaymentDeadline, now)
        : null,
      activationDate: status === 'activa' || status === 'pagada' ? saleDate : null,
      financedBalance: decimal(financedBalance),
      monthlyInterestRate: decimal(monthlyInterest),
      installmentCount,
      balance: decimal(financedBalance),
      raw: { authoritativeSource: 'phase_1d' },
      version: 1,
    },
  });

  if (status === 'activa') {
    const installments = buildInstallmentSchedule({
      saleDate,
      financedBalance,
      monthlyInterest,
      installmentCount,
      statusAsOf: now,
    });
    await tx.installment.createMany({
      data: installments.map((installment) => ({
        companyId: input.companyId,
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

  let initialPaymentId: string | null = null;
  const initialPaymentAmount = input.initialIsApartado ? reservationPaid : initialPaid;
  if (initialPaymentAmount > 0) {
    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId('payment'),
        saleId: sale.id,
        clientId: client.id,
        receivedByUserId: input.operatorUserId,
        saleSyncId: sale.syncId,
        clientSyncId: client.syncId,
        paidAt: saleDate,
        amount: decimal(initialPaymentAmount),
        method: normalizePaymentMethod(input.initialPaymentMethod),
        paymentType:
          input.initialIsApartado || status === 'apartado'
            ? 'apartado'
            : 'abono_inicial',
        reference:
          input.reference ?? `SALE-INIT-${sale.id}-${now.getTime().toString()}`,
        principalApplied: decimal(0),
        interestApplied: decimal(0),
        raw: { authoritativeSource: 'phase_1d' },
      },
      select: { id: true },
    });
    initialPaymentId = payment.id;
  }

  await tx.lot.update({
    where: { id: lot.id },
    data: {
      status: status === 'activa' || status === 'pagada' ? 'vendido' : 'reservado',
      version: { increment: 1 },
    },
  });

  return {
    saleId: sale.id,
    saleSyncId: sale.syncId,
    status,
    balance: financedBalance,
    initialRequiredAmount: requiredInitial,
    initialPaid,
    initialPendingAmount,
    reservationPaidAmount: reservationPaid,
    initialPaymentId,
  };
}

async function cancelSaleInTransaction(
  tx: TransactionClient,
  input: CancelAuthoritativeSaleInput,
): Promise<Prisma.JsonObject> {
  const cancelledAt = parseDate(input.cancelledAt, new Date());
  const sale = await tx.sale.findFirst({
    where: {
      id: input.saleId,
      companyId: input.companyId,
      deletedAt: null,
      NOT: { status: 'cancelada' },
    },
    include: {
      payments: {
        where: { deletedAt: null, annulledAt: null },
        select: { id: true },
      },
    },
  });
  if (!sale) {
    throw new AuthoritativeError('SALE_NOT_FOUND', 'La venta seleccionada no existe.', 404);
  }
  if (sale.payments.length > 0) {
    throw new AuthoritativeError(
      'SALE_CANCELLATION_REQUIRES_PAYMENT_REVERSAL',
      'La venta tiene pagos activos. Debes reversar los pagos antes de cancelar.',
      409,
    );
  }

  await tx.installment.updateMany({
    where: { saleId: sale.id, deletedAt: null },
    data: {
      status: 'cancelada',
      deletedAt: cancelledAt,
      version: { increment: 1 },
    },
  });
  const updatedSale = await tx.sale.update({
    where: { id: sale.id },
    data: {
      status: 'cancelada',
      balance: decimal(0),
      deletedAt: cancelledAt,
      raw: {
        cancelledByUserId: input.cancelledByUserId,
        cancellationReason: input.reason ?? null,
        authoritativeSource: 'phase_1f',
      },
      version: { increment: 1 },
    },
  });
  if (sale.lotId) {
    await tx.lot.update({
      where: { id: sale.lotId },
      data: { status: 'disponible', version: { increment: 1 } },
    });
  }

  return {
    saleId: updatedSale.id,
    status: updatedSale.status,
    cancelledAt: cancelledAt.toISOString(),
    lotId: sale.lotId,
  };
}

async function findActiveClient(tx: TransactionClient, input: CreateAuthoritativeSaleInput) {
  const client = input.clientId
    ? await tx.client.findFirst({
        where: { id: input.clientId, companyId: input.companyId, deletedAt: null },
      })
    : input.clientSyncId
      ? await tx.client.findUnique({
          where: {
            companyId_syncId: {
              companyId: input.companyId,
              syncId: input.clientSyncId,
            },
          },
        })
      : null;
  if (!client || client.deletedAt) {
    throw new AuthoritativeError('CLIENT_NOT_FOUND', 'El cliente seleccionado no existe.', 404);
  }
  return client;
}

async function findActiveLot(tx: TransactionClient, input: CreateAuthoritativeSaleInput) {
  const lot = input.lotId
    ? await tx.lot.findFirst({
        where: { id: input.lotId, companyId: input.companyId, deletedAt: null },
      })
    : input.lotSyncId
      ? await tx.lot.findUnique({
          where: {
            companyId_syncId: {
              companyId: input.companyId,
              syncId: input.lotSyncId,
            },
          },
        })
      : null;
  if (!lot || lot.deletedAt) {
    throw new AuthoritativeError('LOT_NOT_FOUND', 'El solar seleccionado no existe.', 404);
  }
  return lot;
}

async function findActiveSeller(tx: TransactionClient, input: CreateAuthoritativeSaleInput) {
  if (!input.sellerId && !input.sellerSyncId) {
    return null;
  }
  const seller = input.sellerId
    ? await tx.seller.findFirst({
        where: { id: input.sellerId, companyId: input.companyId, deletedAt: null },
      })
    : await tx.seller.findUnique({
        where: {
          companyId_syncId: {
            companyId: input.companyId,
            syncId: input.sellerSyncId ?? '',
          },
        },
      });
  if (!seller || seller.deletedAt) {
    throw new AuthoritativeError('SELLER_NOT_FOUND', 'El vendedor seleccionado no existe.', 404);
  }
  return seller;
}

export function parseDate(value: string | Date | null | undefined, fallback: Date) {
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }
  return fallback;
}

export function decimal(value: number) {
  return new Prisma.Decimal(value.toString());
}

export function toNumber(value: unknown) {
  if (value instanceof Prisma.Decimal) {
    return value.toNumber();
  }
  if (typeof value === 'number') {
    return value;
  }
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function newSyncId(prefix: string) {
  return `${prefix}-${randomUUID()}`;
}

export function normalizePaymentMethod(value: unknown) {
  const text = String(value ?? '').trim();
  return text.length > 0 ? text : 'efectivo';
}
