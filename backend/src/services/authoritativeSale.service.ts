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

type SaleReferenceInput = {
  companyId: string;
  clientId?: string;
  clientSyncId?: string;
  lotId?: string;
  lotSyncId?: string;
  sellerId?: string | null;
  sellerSyncId?: string | null;
};

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

export type UpdateAuthoritativeSaleInput = {
  companyId: string;
  operatorUserId: string;
  idempotencyKey: string;
  saleId: string;
  clientId?: string;
  clientSyncId?: string;
  lotId?: string;
  lotSyncId?: string;
  sellerId?: string | null;
  sellerSyncId?: string | null;
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

export type SaleEditFieldClassification =
  | 'SAFE_EDITABLE'
  | 'FINANCIAL_RECALCULATION_REQUIRED'
  | 'IMMUTABLE_AFTER_PAYMENT'
  | 'FORBIDDEN';

export const saleEditFieldClassification: Record<string, SaleEditFieldClassification> = {
  clientId: 'IMMUTABLE_AFTER_PAYMENT',
  clientSyncId: 'IMMUTABLE_AFTER_PAYMENT',
  sellerId: 'IMMUTABLE_AFTER_PAYMENT',
  sellerSyncId: 'IMMUTABLE_AFTER_PAYMENT',
  lotId: 'IMMUTABLE_AFTER_PAYMENT',
  lotSyncId: 'IMMUTABLE_AFTER_PAYMENT',
  saleDate: 'FINANCIAL_RECALCULATION_REQUIRED',
  salePrice: 'FINANCIAL_RECALCULATION_REQUIRED',
  downPaymentPercentage: 'FINANCIAL_RECALCULATION_REQUIRED',
  initialPercentage: 'FINANCIAL_RECALCULATION_REQUIRED',
  requiredInitialPayment: 'FINANCIAL_RECALCULATION_REQUIRED',
  initialPaymentPaid: 'FINANCIAL_RECALCULATION_REQUIRED',
  initialIsApartado: 'FINANCIAL_RECALCULATION_REQUIRED',
  minimumReserveAmount: 'FINANCIAL_RECALCULATION_REQUIRED',
  initialPaymentDeadline: 'SAFE_EDITABLE',
  monthlyInterest: 'FINANCIAL_RECALCULATION_REQUIRED',
  installmentCount: 'FINANCIAL_RECALCULATION_REQUIRED',
  initialPaymentMethod: 'SAFE_EDITABLE',
  reference: 'SAFE_EDITABLE',
  userId: 'FORBIDDEN',
  status: 'FORBIDDEN',
  balance: 'FORBIDDEN',
  financedBalance: 'FORBIDDEN',
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

  async updateSale(
    input: UpdateAuthoritativeSaleInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: 'sale.update',
        requestPayload: input,
        run: async () => {
          const response = await updateSaleInTransaction(tx, input);
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
      'No puedes eliminar esta venta porque tiene pagos registrados. Anula primero los pagos asociados.',
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

async function updateSaleInTransaction(
  tx: TransactionClient,
  input: UpdateAuthoritativeSaleInput,
): Promise<Prisma.JsonObject> {
  rejectForbiddenSaleEditFields(input);
  const now = new Date();
  const existing = await tx.sale.findFirst({
    where: {
      id: input.saleId,
      companyId: input.companyId,
      deletedAt: null,
      NOT: { status: 'cancelada' },
    },
    include: {
      client: true,
      lot: true,
      seller: true,
      payments: {
        where: { deletedAt: null, annulledAt: null },
        select: { id: true },
      },
      installments: {
        where: { deletedAt: null },
        select: {
          id: true,
          paidAmount: true,
          paidPrincipalAmount: true,
          paidInterestAmount: true,
        },
      },
    },
  });
  if (!existing) {
    throw new AuthoritativeError('SALE_NOT_FOUND', 'La venta seleccionada no existe.', 404);
  }
  if (saleHasActiveFinancialHistory(existing)) {
    throw new AuthoritativeError(
      'SALE_EDIT_BLOCKED_BY_PAYMENTS',
      'No puedes modificar las condiciones financieras de esta venta porque ya tiene pagos registrados.',
      409,
    );
  }

  const client = await findActiveClient(tx, {
    companyId: input.companyId,
    ...clientEditReference(
      { id: input.clientId, syncId: input.clientSyncId },
      { id: existing.clientId, syncId: existing.clientSyncId },
    ),
  });
  const lot = await findActiveLot(tx, {
    companyId: input.companyId,
    ...lotEditReference(
      { id: input.lotId, syncId: input.lotSyncId },
      { id: existing.lotId, syncId: existing.lotSyncId },
    ),
  });
  const seller = await findActiveSeller(tx, {
    companyId: input.companyId,
    ...resolveSellerEditReference(input, {
      sellerId: existing.sellerId,
      sellerSyncId: existing.sellerSyncId,
    }),
  });

  const isChangingLot = lot.id !== existing.lotId;
  if (isChangingLot) {
    if (lot.status && lot.status !== 'disponible') {
      throw new AuthoritativeError(
        'LOT_NOT_AVAILABLE',
        'El nuevo solar seleccionado no esta disponible.',
        409,
      );
    }
    const existingActiveSale = await tx.sale.findFirst({
      where: {
        companyId: input.companyId,
        lotId: lot.id,
        deletedAt: null,
        id: { not: existing.id },
        NOT: { status: 'cancelada' },
      },
      select: { id: true },
    });
    if (existingActiveSale) {
      throw new AuthoritativeError(
        'LOT_ALREADY_SOLD',
        'Ya existe una venta registrada para el nuevo solar.',
        409,
      );
    }
  }

  const saleDate = parseDate(input.saleDate, existing.saleDate ?? now);
  const downPaymentPercentage =
    input.downPaymentPercentage ??
    input.initialPercentage ??
    toNumber(existing.initialPercentage);
  const monthlyInterest = input.monthlyInterest ?? toNumber(existing.monthlyInterestRate);
  const installmentCount = input.installmentCount ?? existing.installmentCount ?? 0;
  const initialPaymentDeadline =
    input.initialPaymentDeadline === undefined
      ? existing.initialPaymentDeadline
      : input.initialPaymentDeadline
        ? parseDate(input.initialPaymentDeadline, now)
        : null;

  if (downPaymentPercentage < 0 || downPaymentPercentage > 100) {
    throw new AuthoritativeError(
      'INVALID_INITIAL_PERCENTAGE',
      'El porcentaje de inicial debe estar entre 0% y 100%.',
    );
  }
  if (monthlyInterest < 0) {
    throw new AuthoritativeError('INVALID_MONTHLY_INTEREST', 'El interes mensual no puede ser negativo.');
  }
  if (installmentCount <= 0) {
    throw new AuthoritativeError('INVALID_INSTALLMENT_COUNT', 'La venta debe generar al menos una cuota.');
  }

  const salePrice =
    input.salePrice && input.salePrice > 0
      ? roundCurrency(input.salePrice)
      : roundCurrency(toNumber(lot.area) * toNumber(lot.price));
  if (salePrice <= 0) {
    throw new AuthoritativeError('INVALID_LOT_PRICE', 'La venta debe tener un precio total valido.');
  }
  const requiredInitial = roundCurrency(
    input.requiredInitialPayment ??
      calculateDownPaymentAmount({
        salePrice,
        downPaymentPercentage,
      }),
  );
  const existingInitialIsApartado =
    toNumber(existing.reservationPaidAmount) > 0.009 &&
    toNumber(existing.initialPaid) <= 0.009;
  const initialIsApartado = input.initialIsApartado ?? existingInitialIsApartado;
  const providedAmount = roundCurrency(
    input.initialPaymentPaid ??
      (initialIsApartado
        ? toNumber(existing.reservationPaidAmount)
        : toNumber(existing.initialPaid)),
  );
  const initialPaid = initialIsApartado ? 0 : providedAmount;
  const reservationPaid = initialIsApartado ? providedAmount : 0;
  const minimumReserveAmount =
    input.minimumReserveAmount == null
      ? roundCurrency(toNumber(existing.reservationMinimumAmount))
      : roundCurrency(input.minimumReserveAmount);

  if (initialPaid < 0 || reservationPaid < 0) {
    throw new AuthoritativeError('INVALID_INITIAL_PAYMENT', 'El inicial pagado no puede ser negativo.');
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
  if (initialPaid + 0.009 < requiredInitial && !initialPaymentDeadline) {
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

  await tx.installment.updateMany({
    where: { saleId: existing.id, deletedAt: null },
    data: {
      status: 'cancelada',
      deletedAt: now,
      version: { increment: 1 },
    },
  });

  const updatedSale = await tx.sale.update({
    where: { id: existing.id },
    data: {
      clientId: client.id,
      lotId: lot.id,
      sellerId: seller?.id,
      operatorUserId: input.operatorUserId || existing.operatorUserId,
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
      initialPaymentDeadline,
      activationDate: status === 'activa' || status === 'pagada' ? saleDate : null,
      financedBalance: decimal(financedBalance),
      monthlyInterestRate: decimal(monthlyInterest),
      installmentCount,
      balance: decimal(financedBalance),
      raw: { authoritativeSource: 'phase_sale_edit' },
      version: { increment: 1 },
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
        saleId: updatedSale.id,
        saleSyncId: updatedSale.syncId,
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
        raw: { authoritativeSource: 'phase_sale_edit' },
      })),
    });
  }

  let initialPaymentId: string | null = null;
  const initialPaymentAmount = initialIsApartado ? reservationPaid : initialPaid;
  if (initialPaymentAmount > 0) {
    const payment = await tx.payment.create({
      data: {
        companyId: input.companyId,
        syncId: newSyncId('payment'),
        saleId: updatedSale.id,
        clientId: client.id,
        receivedByUserId: input.operatorUserId,
        saleSyncId: updatedSale.syncId,
        clientSyncId: client.syncId,
        paidAt: saleDate,
        amount: decimal(initialPaymentAmount),
        method: normalizePaymentMethod(input.initialPaymentMethod),
        paymentType:
          initialIsApartado || status === 'apartado'
            ? 'apartado'
            : 'abono_inicial',
        reference:
          input.reference ?? `SALE-EDIT-INIT-${updatedSale.id}-${now.getTime().toString()}`,
        principalApplied: decimal(0),
        interestApplied: decimal(0),
        raw: { authoritativeSource: 'phase_sale_edit' },
      },
      select: { id: true },
    });
    initialPaymentId = payment.id;
  }

  if (isChangingLot && existing.lotId) {
    await tx.lot.update({
      where: { id: existing.lotId },
      data: { status: 'disponible', version: { increment: 1 } },
    });
  }
  await tx.lot.update({
    where: { id: lot.id },
    data: {
      status: status === 'activa' || status === 'pagada' ? 'vendido' : 'reservado',
      version: { increment: 1 },
    },
  });

  return {
    saleId: updatedSale.id,
    saleSyncId: updatedSale.syncId,
    status,
    balance: financedBalance,
    initialRequiredAmount: requiredInitial,
    initialPaid,
    initialPendingAmount,
    reservationPaidAmount: reservationPaid,
    initialPaymentId,
    previousLotId: isChangingLot ? existing.lotId : null,
    lotId: lot.id,
  };
}

function rejectForbiddenSaleEditFields(input: UpdateAuthoritativeSaleInput) {
  for (const [field, classification] of Object.entries(saleEditFieldClassification)) {
    if (classification === 'FORBIDDEN' && (input as Record<string, unknown>)[field] !== undefined) {
      throw new AuthoritativeError(
        'SALE_EDIT_FIELD_FORBIDDEN',
        `El campo ${field} no puede editarse directamente en una venta.`,
      );
    }
  }
}

export function saleHasActiveFinancialHistory(sale: {
  payments?: Array<unknown>;
  installments?: Array<{
    paidAmount?: unknown;
    paidPrincipalAmount?: unknown;
    paidInterestAmount?: unknown;
  }>;
}) {
  if ((sale.payments?.length ?? 0) > 0) {
    return true;
  }
  return (sale.installments ?? []).some(
    (installment) =>
      toNumber(installment.paidAmount) > 0.009 ||
      toNumber(installment.paidPrincipalAmount) > 0.009 ||
      toNumber(installment.paidInterestAmount) > 0.009,
  );
}

function resolveSellerEditReference(
  input: UpdateAuthoritativeSaleInput,
  existing: { sellerId?: string | null; sellerSyncId?: string | null },
) {
  if (input.sellerId === null || input.sellerSyncId === null) {
    return { sellerId: null, sellerSyncId: null };
  }
  if (input.sellerId !== undefined) {
    return { sellerId: input.sellerId, sellerSyncId: undefined };
  }
  if (input.sellerSyncId !== undefined) {
    return { sellerId: undefined, sellerSyncId: input.sellerSyncId };
  }
  return {
    sellerId: existing.sellerId,
    sellerSyncId: existing.sellerSyncId,
  };
}

export function resolveSaleEditReferenceForTest(
  input: { id?: string; syncId?: string },
  existing: { id?: string | null; syncId?: string | null },
) {
  return resolveRequiredEditReference(input, existing);
}

function clientEditReference(
  input: { id?: string; syncId?: string },
  existing: { id?: string | null; syncId?: string | null },
) {
  const resolved = resolveRequiredEditReference(input, existing);
  return { clientId: resolved.id, clientSyncId: resolved.syncId };
}

function lotEditReference(
  input: { id?: string; syncId?: string },
  existing: { id?: string | null; syncId?: string | null },
) {
  const resolved = resolveRequiredEditReference(input, existing);
  return { lotId: resolved.id, lotSyncId: resolved.syncId };
}

function resolveRequiredEditReference(
  input: { id?: string; syncId?: string },
  existing: { id?: string | null; syncId?: string | null },
) {
  if (input.id !== undefined) {
    return { id: input.id, syncId: undefined };
  }
  if (input.syncId !== undefined) {
    return { id: undefined, syncId: input.syncId };
  }
  return {
    id: existing.id ?? undefined,
    syncId: existing.syncId ?? undefined,
  };
}

async function findActiveClient(tx: TransactionClient, input: SaleReferenceInput) {
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

async function findActiveLot(tx: TransactionClient, input: SaleReferenceInput) {
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

async function findActiveSeller(tx: TransactionClient, input: SaleReferenceInput) {
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
