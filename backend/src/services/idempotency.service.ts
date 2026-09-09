import { createHash } from 'crypto';
import { Prisma } from '@prisma/client';
import { AuthoritativeError } from './authoritativeErrors.service';

type TransactionClient = Prisma.TransactionClient;

export type IdempotentResult<T> = {
  response: T;
  replayed: boolean;
};

export function requireIdempotencyKey(value: unknown) {
  const key = String(value ?? '').trim();
  if (!key) {
    throw new AuthoritativeError(
      'IDEMPOTENCY_KEY_REQUIRED',
      'Debes enviar Idempotency-Key para operaciones autoritativas.',
      400,
    );
  }
  if (key.length > 160) {
    throw new AuthoritativeError(
      'IDEMPOTENCY_KEY_TOO_LONG',
      'Idempotency-Key excede el largo maximo permitido.',
      400,
    );
  }
  return key;
}

export function stableRequestHash(operationType: string, payload: unknown) {
  return createHash('sha256')
    .update(stableStringify({ operationType, payload }))
    .digest('hex');
}

export async function runIdempotentOperation<T extends Prisma.JsonObject>(
  tx: TransactionClient,
  input: {
    companyId: string;
    operationKey: string;
    operationType: string;
    requestPayload: unknown;
    run: () => Promise<{ response: T; resourceType?: string; resourceId?: string }>;
  },
): Promise<IdempotentResult<T>> {
  const requestHash = stableRequestHash(input.operationType, input.requestPayload);
  const existing = await tx.authoritativeOperation.findUnique({
    where: {
      companyId_operationKey: {
        companyId: input.companyId,
        operationKey: input.operationKey,
      },
    },
  });

  if (existing) {
    if (existing.requestHash !== requestHash) {
      throw new AuthoritativeError(
        'IDEMPOTENCY_KEY_CONFLICT',
        'La llave idempotente ya fue usada con un payload distinto.',
        409,
      );
    }
    return {
      response: (existing.response ?? {}) as T,
      replayed: true,
    };
  }

  const result = await input.run();
  await tx.authoritativeOperation.create({
    data: {
      companyId: input.companyId,
      operationKey: input.operationKey,
      operationType: input.operationType,
      requestHash,
      resourceType: result.resourceType,
      resourceId: result.resourceId,
      response: result.response,
    },
  });

  return { response: result.response, replayed: false };
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(',')}]`;
  }

  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(',')}}`;
}
