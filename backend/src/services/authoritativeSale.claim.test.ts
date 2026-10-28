import assert from 'node:assert/strict';
import test from 'node:test';
import type { PrismaClient } from '@prisma/client';
import { AuthoritativeSaleService } from './authoritativeSale.service';
import { AuthoritativeError } from './authoritativeErrors.service';

/**
 * Regresion del control de concurrencia del alta de venta.
 *
 * El servicio reclama el solar con un UPDATE condicionado a
 * `status = 'disponible'` (compare-and-set). Estos tests fijan la semantica:
 *  - si el solar ya fue tomado (count = 0) -> 409 LOT_JUST_TAKEN y NINGUNA
 *    venta/cuota/pago creados,
 *  - el reclamo ocurre ANTES de crear la venta,
 *  - el pre-chequeo de estado del solar sigue vigente (no se relajo nada).
 */

type Call = { method: string; args?: unknown };

function buildHarness(options: {
  lotStatus?: string | null;
  claimCount?: number;
  existingActiveSale?: boolean;
}) {
  const calls: Call[] = [];
  const record = (method: string, args?: unknown) => {
    calls.push({ method, args });
  };

  const client = {
    id: 'client-1',
    companyId: 'company-1',
    syncId: 'client-sync-1',
    deletedAt: null,
  };
  const lot = {
    id: 'lot-1',
    companyId: 'company-1',
    syncId: 'lot-sync-1',
    status: options.lotStatus ?? 'disponible',
    area: 200,
    price: 3000,
    deletedAt: null,
  };

  const tx = {
    financialParameters: {
      findUnique: async (args: unknown) => {
        record('financialParameters.findUnique', args);
        return null;
      },
    },
    client: {
      findFirst: async (args: unknown) => {
        record('client.findFirst', args);
        return client;
      },
      findUnique: async (args: unknown) => {
        record('client.findUnique', args);
        return client;
      },
    },
    lot: {
      findFirst: async (args: unknown) => {
        record('lot.findFirst', args);
        return lot;
      },
      findUnique: async (args: unknown) => {
        record('lot.findUnique', args);
        return lot;
      },
      updateMany: async (args: unknown) => {
        record('lot.updateMany', args);
        return { count: options.claimCount ?? 1 };
      },
      update: async (args: unknown) => {
        record('lot.update', args);
        return lot;
      },
    },
    seller: {
      findFirst: async (args: unknown) => {
        record('seller.findFirst', args);
        return null;
      },
      findUnique: async (args: unknown) => {
        record('seller.findUnique', args);
        return null;
      },
    },
    sale: {
      findFirst: async (args: unknown) => {
        record('sale.findFirst', args);
        return options.existingActiveSale ? { id: 'sale-existing' } : null;
      },
      create: async (args: unknown) => {
        record('sale.create', args);
        return { id: 'sale-1', syncId: 'sale-sync-1' };
      },
    },
    installment: {
      createMany: async (args: unknown) => {
        record('installment.createMany', args);
        return { count: 12 };
      },
      updateMany: async (args: unknown) => {
        record('installment.updateMany', args);
        return { count: 0 };
      },
    },
    payment: {
      create: async (args: unknown) => {
        record('payment.create', args);
        return { id: 'payment-1' };
      },
    },
    authoritativeOperation: {
      findUnique: async (args: unknown) => {
        record('authoritativeOperation.findUnique', args);
        return null;
      },
      create: async (args: unknown) => {
        record('authoritativeOperation.create', args);
        return { id: 'op-1' };
      },
    },
  };

  const prisma = {
    $transaction: async (fn: (t: unknown) => Promise<unknown>) => fn(tx),
  } as unknown as PrismaClient;

  return { prisma, calls };
}

const baseInput = {
  companyId: 'company-1',
  operatorUserId: 'user-1',
  idempotencyKey: 'op-key-1',
  clientId: 'client-1',
  lotId: 'lot-1',
  saleDate: '2026-10-27T15:00:00.000Z',
  salePrice: 600000,
  downPaymentPercentage: 10,
  initialPaymentPaid: 60000,
  monthlyInterest: 1,
  installmentCount: 12,
  initialPaymentMethod: 'efectivo',
  saleType: 'FINANCED',
};

test('solar ya tomado por otra venta: 409 y sin efectos financieros', async () => {
  const { prisma, calls } = buildHarness({ claimCount: 0 });
  const service = new AuthoritativeSaleService(prisma);

  await assert.rejects(
    () => service.createSale({ ...baseInput, idempotencyKey: 'op-key-taken' }),
    (error: unknown) => {
      assert.ok(error instanceof AuthoritativeError);
      assert.equal(error.code, 'LOT_JUST_TAKEN');
      assert.equal(error.httpStatus, 409);
      return true;
    },
  );

  const methods = calls.map((call) => call.method);
  assert.ok(methods.includes('lot.updateMany'));
  assert.equal(methods.includes('sale.create'), false);
  assert.equal(methods.includes('installment.createMany'), false);
  assert.equal(methods.includes('payment.create'), false);
});

test('el reclamo del solar ocurre antes de crear la venta', async () => {
  const { prisma, calls } = buildHarness({ claimCount: 1 });
  const service = new AuthoritativeSaleService(prisma);

  const result = await service.createSale(baseInput);

  assert.equal(result.response.saleId, 'sale-1');
  const methods = calls.map((call) => call.method);
  const claimIndex = methods.indexOf('lot.updateMany');
  const saleIndex = methods.indexOf('sale.create');
  assert.ok(claimIndex >= 0 && saleIndex >= 0);
  assert.ok(claimIndex < saleIndex);
  // Ya no se ejecuta el update incondicional posterior.
  assert.equal(methods.includes('lot.update'), false);
});

test('solar no disponible sigue rechazandose antes de cualquier escritura', async () => {
  const { prisma, calls } = buildHarness({ lotStatus: 'vendido', claimCount: 0 });
  const service = new AuthoritativeSaleService(prisma);

  await assert.rejects(
    () => service.createSale({ ...baseInput, idempotencyKey: 'op-key-sold' }),
    (error: unknown) => {
      assert.ok(error instanceof AuthoritativeError);
      assert.equal(error.code, 'LOT_NOT_AVAILABLE');
      assert.equal(error.httpStatus, 409);
      return true;
    },
  );

  const methods = calls.map((call) => call.method);
  assert.equal(methods.includes('lot.updateMany'), false);
  assert.equal(methods.includes('sale.create'), false);
});

test('solar con venta activa previa sigue bloqueado (409 LOT_ALREADY_SOLD)', async () => {
  const { prisma, calls } = buildHarness({
    claimCount: 1,
    existingActiveSale: true,
  });
  const service = new AuthoritativeSaleService(prisma);

  await assert.rejects(
    () => service.createSale({ ...baseInput, idempotencyKey: 'op-key-dup' }),
    (error: unknown) => {
      assert.ok(error instanceof AuthoritativeError);
      assert.equal(error.code, 'LOT_ALREADY_SOLD');
      assert.equal(error.httpStatus, 409);
      return true;
    },
  );

  const methods = calls.map((call) => call.method);
  assert.equal(methods.includes('sale.create'), false);
});
