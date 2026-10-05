import { Prisma } from '@prisma/client';
import { config } from '../config';
import {
  DEFAULT_LATE_FEE_DAILY_RATE,
  DEFAULT_LATE_FEE_ENABLED,
  DEFAULT_LATE_FEE_GRACE_DAYS,
} from './lateFeeCalculation.service';

export const LATE_FEE_CONFIG_KEYS = {
  enabled: 'late_fee_enabled',
  dailyRate: 'late_fee_daily_rate',
  graceDays: 'late_fee_grace_days',
} as const;

export type LateFeePolicy = {
  enabled: boolean;
  dailyRate: string;
  graceDays: number;
  effectiveFrom?: Date | null;
};

type BusinessConfigurationReader = {
  businessConfiguration: {
    findMany(args: {
      where: {
        companyId: string;
        key: { in: string[] };
        deletedAt: null;
      };
    }): Promise<Array<{ key: string; value: string | null; valueJson: Prisma.JsonValue | null }>>;
  };
  lateFeePolicyHistory?: {
    findFirst(args: {
      where: {
        companyId: string;
        effectiveFrom: { lte: Date };
      };
      orderBy: Array<{ effectiveFrom: 'desc' } | { createdAt: 'desc' }>;
    }): Promise<{ enabled: boolean; dailyRate: Prisma.Decimal; graceDays: number; effectiveFrom: Date } | null>;
  };
};

export function defaultLateFeePolicy(): LateFeePolicy {
  return {
    enabled: parseBoolean(config.lateFeeEnabled, DEFAULT_LATE_FEE_ENABLED),
    dailyRate: normalizeDailyRate(config.lateFeeDailyRate),
    graceDays: normalizeGraceDays(config.lateFeeGraceDays),
  };
}

export async function readLateFeePolicy(
  db: BusinessConfigurationReader,
  companyId: string,
  asOf = new Date(),
): Promise<LateFeePolicy> {
  const defaults = defaultLateFeePolicy();
  const history = await db.lateFeePolicyHistory?.findFirst({
    where: {
      companyId,
      effectiveFrom: { lte: asOf },
    },
    orderBy: [{ effectiveFrom: 'desc' }, { createdAt: 'desc' }],
  });
  const rows = await db.businessConfiguration.findMany({
    where: {
      companyId,
      key: { in: Object.values(LATE_FEE_CONFIG_KEYS) },
      deletedAt: null,
    },
  });
  const values = new Map(rows.map((row) => [row.key, row.value]));
  return {
    enabled: parseBoolean(values.get(LATE_FEE_CONFIG_KEYS.enabled), history?.enabled ?? defaults.enabled),
    dailyRate: normalizeDailyRate(values.get(LATE_FEE_CONFIG_KEYS.dailyRate) ?? history?.dailyRate?.toString() ?? defaults.dailyRate),
    graceDays: normalizeGraceDays(values.get(LATE_FEE_CONFIG_KEYS.graceDays) ?? history?.graceDays ?? defaults.graceDays),
    effectiveFrom: history?.effectiveFrom ?? null,
  };
}

function parseBoolean(value: unknown, fallback: boolean) {
  if (typeof value === 'boolean') return value;
  const normalized = String(value ?? '').trim().toLowerCase();
  if (['true', '1', 'yes', 'si', 'sí'].includes(normalized)) return true;
  if (['false', '0', 'no'].includes(normalized)) return false;
  return fallback;
}

function normalizeDailyRate(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1) return DEFAULT_LATE_FEE_DAILY_RATE;
  return new Prisma.Decimal(parsed).toString();
}

function normalizeGraceDays(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) return DEFAULT_LATE_FEE_GRACE_DAYS;
  return Math.trunc(parsed);
}
