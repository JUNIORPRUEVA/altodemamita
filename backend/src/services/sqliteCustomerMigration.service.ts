import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { Prisma, PrismaClient, UserRole } from '@prisma/client';

export type Severity = 'PASS' | 'REPAIRABLE_ON_WORKING_COPY' | 'BLOCKING';

export type Row = Record<string, unknown>;

export type TableBundle = Record<string, Row[]>;

export type MigrationCliOptions = {
  source: string;
  target?: string;
  outputDir: string;
  precheck: boolean;
  migrate: boolean;
  reconcile: boolean;
  deploySchema: boolean;
  allowSqlFallback: boolean;
  allowWorkingCopyRepair: boolean;
  repeatability: boolean;
  replay: boolean;
  companyTenantKey: string;
  companyName: string;
};

export type MigrationReport = {
  startedAt: string;
  finishedAt?: string;
  source: SourceSafetyReport;
  precheck?: PrecheckReport;
  financialNormalization?: FinancialNormalizationReport;
  schemaDeploy?: SchemaDeployReport;
  migration?: ImportReport;
  reconciliation?: ReconciliationReport;
  repeatability?: RepeatabilityReport;
  finalStatus: Severity;
  p0: string[];
};

export type SourceSafetyReport = {
  originalPath: string;
  originalSha256Before: string;
  originalSha256After?: string;
  originalUnchanged?: boolean;
  workingCopyPath: string;
  workingCopySha256BeforeRepair: string;
  workingCopySha256AfterRepair?: string;
  sidecars: SidecarReport[];
  repairActions: string[];
};

export type SidecarReport = {
  suffix: '.db' | '.db-wal' | '.db-shm' | '.db-journal';
  path: string;
  exists: boolean;
  size: number | null;
  modifiedAt: string | null;
};

export type PrecheckReport = {
  status: Severity;
  userVersion: number;
  tableCount: number;
  integrity: string[];
  quickCheck: string[];
  tableCounts: Record<string, number>;
  activeCounts: Record<string, number>;
  deletedCounts: Record<string, number>;
  statusCounts: Record<string, Record<string, number>>;
  syncIdentity: CheckResult[];
  relationships: CheckResult[];
  financial: CheckResult[];
  businessConfig: BusinessConfigClassification[];
  messages: string[];
};

export type CheckResult = {
  check: string;
  status: Severity;
  count?: number;
  message: string;
};

export type BusinessConfigClassification = {
  key: string;
  classification: ConfigClassification;
  migrated: boolean;
};

export type FinancialNormalizationReport = {
  status: Severity;
  policy: 'PRESERVE_SALE_BALANCE_ADJUST_FINAL_ELIGIBLE_INSTALLMENT';
  affectedActiveSales: number;
  normalizedSales: number;
  unexplainedSales: number;
  positiveDeltas: number;
  negativeDeltas: number;
  minDelta: string;
  maxDelta: string;
  sumAbsoluteDelta: string;
  classifications: Record<string, number>;
  entries: FinancialNormalizationEntry[];
  messages: string[];
};

export type FinancialNormalizationEntry = {
  saleHash: string;
  classification: 'ROUNDING_RESIDUAL' | 'UNEXPLAINED';
  action: 'ADJUST_FINAL_ELIGIBLE_INSTALLMENT_PRINCIPAL' | 'NONE';
  installmentCount: number;
  beforeRemainingPrincipal: string;
  saleBalance: string;
  delta: string;
  adjustedInstallmentHash?: string;
  adjustedInstallmentNumber?: number | null;
  principalBefore?: string;
  principalAfter?: string;
};

export type ConfigClassification =
  | 'CLOUD_BUSINESS'
  | 'LEGACY_TECHNICAL_CONFIG'
  | 'DEVICE_LOCAL'
  | 'AUTH_SESSION'
  | 'SYNC_RUNTIME'
  | 'BACKUP_LOCAL'
  | 'PRINTER_LOCAL'
  | 'UNKNOWN';

export type ImportReport = {
  status: Severity;
  companyId: string;
  counts: Record<string, number>;
};

export type ReconciliationReport = {
  status: Severity;
  counts: Record<string, ReconciliationEntry>;
  statuses: Record<string, Record<string, ReconciliationEntry>>;
  softDeletes: Record<string, ReconciliationEntry>;
  relationships: CheckResult[];
  syncIdentities: CheckResult[];
  financial: Record<string, MoneyReconciliationEntry>;
  activeSaleBalances: ActiveSaleBalanceReconciliation;
  tolerance: number;
  messages: string[];
};

export type ActiveSaleBalanceReconciliation = {
  status: Severity;
  checked: number;
  mismatches: number;
  maxDelta: string;
};

export type ReconciliationEntry = {
  sqlite: number;
  postgres: number;
  delta: number;
  passed: boolean;
};

export type MoneyReconciliationEntry = {
  sqliteRaw: string;
  sqliteNormalized: string;
  postgres: string;
  delta: string;
  passed: boolean;
};

export type RepeatabilityReport = {
  status: Severity;
  cleanRunSame: boolean;
  replaySame: boolean;
  messages: string[];
};

export type SchemaDeployReport = {
  status: Severity;
  prismaMigrateDeploy: 'PASS' | 'FAIL' | 'SKIPPED';
  fallbackUsed: boolean;
  fallbackStatus?: 'PASS' | 'FAIL';
  messages: string[];
};

const businessTables = [
  'clientes',
  'vendedores',
  'solares',
  'ventas',
  'cuotas',
  'pagos',
  'usuarios',
  'roles',
  'permisos',
  'user_roles',
  'role_permissions',
  'company_profiles',
  'informacion_empresa',
  'parametros_financieros',
  'configuracion',
] as const;

const syncTables = [
  'clientes',
  'vendedores',
  'solares',
  'ventas',
  'cuotas',
  'pagos',
  'usuarios',
  'roles',
  'permisos',
  'user_roles',
  'role_permissions',
  'company_profiles',
] as const;

const cloudBusinessConfigKeys = new Set([
  'business_name',
  'currency_symbol',
  'default_payment_method',
  'sale_default_down_payment_percentage',
  'sale_default_installment_count',
  'sale_default_monthly_interest',
]);

const legacyTechnicalConfigPatterns = [
  'backend_url',
  'base_url',
  'api_url',
  'sync_url',
  'database_host',
  'database_port',
  'postgres',
  'postgresql',
  'easypanel',
  'host',
  'hostname',
  'server',
  'token',
];

const validStatuses: Record<string, Set<string>> = {
  solares: new Set(['disponible', 'reservado', 'vendido']),
  ventas: new Set(['apartado', 'inicial_incompleto', 'activa', 'pagada', 'cancelada']),
  cuotas: new Set(['pendiente', 'vencida', 'parcial', 'pagada', 'ajustada', 'cancelada']),
  pagos: new Set(['apartado', 'abono_inicial', 'cuota', 'abono_capital']),
};

const moneyTolerance = new Prisma.Decimal('0.009');
const activeSaleBalanceTolerance = new Prisma.Decimal('0.01');

export function normalizeMoney(value: unknown): Prisma.Decimal {
  const numeric = Number(value ?? 0);
  if (!Number.isFinite(numeric)) {
    throw new Error(`Invalid money value: ${String(value)}`);
  }
  return new Prisma.Decimal(Math.round((numeric + Number.EPSILON) * 100)).div(100);
}

export function normalizeMoneyString(value: unknown): string {
  return normalizeMoney(value).toFixed(2);
}

function moneyCents(value: unknown): number {
  return normalizeMoney(value).mul(100).round().toNumber();
}

function centsString(cents: number): string {
  return new Prisma.Decimal(cents).div(100).toFixed(2);
}

function hashAuditKey(value: string): string {
  return createHash('sha256').update(`sistema-solares-migration-audit:${value}`).digest('hex').slice(0, 16);
}

export function sumNormalizedMoney(rows: Row[], key: string): Prisma.Decimal {
  return rows.reduce(
    (sum, row) => sum.plus(normalizeMoney(row[key])),
    new Prisma.Decimal(0),
  );
}

export function classifyBusinessConfigKey(key: string): ConfigClassification {
  const normalizedKey = key.toLowerCase();
  if (cloudBusinessConfigKeys.has(key)) return 'CLOUD_BUSINESS';
  if (key.startsWith('auth.')) return 'AUTH_SESSION';
  if (key.startsWith('sync.')) return 'SYNC_RUNTIME';
  if (legacyTechnicalConfigPatterns.some((pattern) => normalizedKey.includes(pattern))) {
    return 'LEGACY_TECHNICAL_CONFIG';
  }
  if (key.includes('backup')) return 'BACKUP_LOCAL';
  if (key.includes('printer') || key.includes('impresora')) return 'PRINTER_LOCAL';
  if (key.startsWith('device.') || key === 'lot_repair_v1_completed' || key === 'lot_repair_v1_completed_at') {
    return 'DEVICE_LOCAL';
  }
  return 'UNKNOWN';
}

export function deterministicUuid(scope: string, key: string): string {
  const hash = createHash('sha1').update(`sistema-solares:${scope}:${key}`).digest();
  const bytes = Buffer.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join('-');
}

export async function runCustomerSqliteMigration(
  options: MigrationCliOptions,
  prisma = new PrismaClient({ datasources: options.target ? { db: { url: options.target } } : undefined }),
): Promise<MigrationReport> {
  const report: MigrationReport = {
    startedAt: new Date().toISOString(),
    source: prepareSourceCopy(options),
    finalStatus: 'PASS',
    p0: [],
  };

  try {
    if (options.precheck) {
      report.precheck = runPrecheck(report.source.workingCopyPath);
      if (report.precheck.status === 'REPAIRABLE_ON_WORKING_COPY') {
        if (!options.allowWorkingCopyRepair) {
          report.p0.push('Precheck requires working-copy repair but --allow-working-copy-repair was not supplied.');
        } else {
          const actions = repairWorkingCopy(report.source.workingCopyPath, report.precheck);
          report.source.repairActions.push(...actions);
          report.source.workingCopySha256AfterRepair = sha256(report.source.workingCopyPath);
          report.precheck = runPrecheck(report.source.workingCopyPath);
        }
      }
      if (report.precheck.status !== 'PASS') {
        report.p0.push(...report.precheck.messages);
      }
    }

    if (report.p0.length === 0 && options.deploySchema) {
      report.schemaDeploy = deploySchema(options);
      if (report.schemaDeploy.status !== 'PASS') {
        report.p0.push(...report.schemaDeploy.messages);
      }
    }

    let bundle: TableBundle | null = null;
    let companyId: string | null = null;
    if (report.p0.length === 0 && (options.migrate || options.reconcile)) {
      bundle = readSqliteBundle(report.source.workingCopyPath);
      report.financialNormalization = normalizeActiveSaleBalances(bundle);
      if (report.financialNormalization.status !== 'PASS') {
        report.p0.push(...report.financialNormalization.messages);
      }
    }

    if (report.p0.length === 0 && options.migrate && bundle) {
      report.migration = await importBundle(prisma, bundle, options);
      companyId = report.migration.companyId;
    }

    if (report.p0.length === 0 && options.reconcile && bundle) {
      if (!companyId) {
        companyId = deterministicUuid('company', options.companyTenantKey);
      }
      report.reconciliation = await reconcile(prisma, bundle, companyId);
      if (report.reconciliation.status !== 'PASS') {
        report.p0.push(...report.reconciliation.messages);
      }
    }

    report.source.originalSha256After = sha256(options.source);
    report.source.originalUnchanged =
      report.source.originalSha256Before === report.source.originalSha256After;
    if (!report.source.originalUnchanged) {
      report.p0.push('Source SQLite SHA256 changed during migration.');
    }
  } finally {
    await prisma.$disconnect();
  }

  report.finishedAt = new Date().toISOString();
  report.finalStatus = report.p0.length === 0 ? 'PASS' : 'BLOCKING';
  writeReports(report, options.outputDir);
  return report;
}

export function prepareSourceCopy(options: MigrationCliOptions): SourceSafetyReport {
  const source = resolve(options.source);
  if (!existsSync(source)) {
    throw new Error(`Source SQLite copy does not exist: ${source}`);
  }
  const outputDir = resolve(options.outputDir);
  mkdirSync(outputDir, { recursive: true });
  const workingCopyPath = join(outputDir, `working_copy_${basename(source)}`);
  copyFileSync(source, workingCopyPath);
  for (const suffix of ['-wal', '-shm', '-journal']) {
    const sidecar = `${source}${suffix}`;
    if (existsSync(sidecar)) {
      copyFileSync(sidecar, `${workingCopyPath}${suffix}`);
    }
  }
  return {
    originalPath: source,
    originalSha256Before: sha256(source),
    workingCopyPath,
    workingCopySha256BeforeRepair: sha256(workingCopyPath),
    sidecars: sidecarReport(source),
    repairActions: [],
  };
}

export function sidecarReport(source: string): SidecarReport[] {
  return (['.db', '.db-wal', '.db-shm', '.db-journal'] as const).map((suffix) => {
    const path = suffix === '.db' ? source : `${source}${suffix.replace('.db', '')}`;
    if (!existsSync(path)) {
      return { suffix, path, exists: false, size: null, modifiedAt: null };
    }
    const stats = statSync(path);
    return {
      suffix,
      path,
      exists: true,
      size: stats.size,
      modifiedAt: stats.mtime.toISOString(),
    };
  });
}

export function runPrecheck(sqlitePath: string): PrecheckReport {
  const integrity = sqliteScalarRows(sqlitePath, 'PRAGMA integrity_check;');
  const quickCheck = sqliteScalarRows(sqlitePath, 'PRAGMA quick_check;');
  const existingTables = new Set(
    sqliteRows(sqlitePath, "SELECT name FROM sqlite_master WHERE type='table';")
      .map((row) => stringValue(row.name))
      .filter(Boolean) as string[],
  );
  const messages: string[] = [];
  const syncIdentity: CheckResult[] = [];
  const relationships: CheckResult[] = [];
  const financial: CheckResult[] = [];
  const tableCounts: Record<string, number> = {};
  const activeCounts: Record<string, number> = {};
  const deletedCounts: Record<string, number> = {};
  const statusCounts: Record<string, Record<string, number>> = {};

  for (const table of businessTables) {
    if (!existingTables.has(table)) {
      messages.push(`Missing expected table: ${table}`);
      continue;
    }
    tableCounts[table] = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM ${table};`);
    if (hasColumn(sqlitePath, table, 'deleted_at')) {
      activeCounts[table] = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM ${table} WHERE deleted_at IS NULL;`);
      deletedCounts[table] = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM ${table} WHERE deleted_at IS NOT NULL;`);
    }
  }

  for (const table of syncTables) {
    if (!existingTables.has(table) || !hasColumn(sqlitePath, table, 'sync_id')) continue;
    const missing = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM ${table} WHERE sync_id IS NULL OR TRIM(sync_id) = '';`);
    syncIdentity.push(checkCount(`${table}.sync_id missing`, missing));
    const duplicates = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM (SELECT sync_id FROM ${table} WHERE sync_id IS NOT NULL AND TRIM(sync_id) <> '' GROUP BY sync_id HAVING COUNT(*) > 1);`);
    syncIdentity.push(checkCount(`${table}.sync_id duplicate groups`, duplicates));
    const malformed = sqliteCount(sqlitePath, `SELECT COUNT(*) AS count FROM ${table} WHERE sync_id IS NOT NULL AND TRIM(sync_id) <> '' AND (sync_id GLOB '*[[:space:]]*' OR LENGTH(sync_id) > 191);`);
    syncIdentity.push(checkCount(`${table}.sync_id malformed`, malformed));
  }

  relationships.push(checkCount('ventas.cliente_id orphans', orphanCount(sqlitePath, 'ventas', 'cliente_id', 'clientes')));
  relationships.push(checkCount('ventas.solar_id orphans', orphanCount(sqlitePath, 'ventas', 'solar_id', 'solares')));
  relationships.push(checkCount('ventas.vendedor_id orphans', orphanCount(sqlitePath, 'ventas', 'vendedor_id', 'vendedores')));
  relationships.push(checkCount('ventas.usuario_id orphans', orphanCount(sqlitePath, 'ventas', 'usuario_id', 'usuarios')));
  relationships.push(checkCount('cuotas.venta_id orphans', orphanCount(sqlitePath, 'cuotas', 'venta_id', 'ventas')));
  relationships.push(checkCount('pagos.venta_id orphans', orphanCount(sqlitePath, 'pagos', 'venta_id', 'ventas')));
  relationships.push(checkCount('pagos.cliente_id orphans', orphanCount(sqlitePath, 'pagos', 'cliente_id', 'clientes')));
  relationships.push(checkCount('pagos.cuota_id orphans', orphanCount(sqlitePath, 'pagos', 'cuota_id', 'cuotas')));
  relationships.push(checkCount('duplicate active sale per lot', sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count FROM (
      SELECT solar_id FROM ventas
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(estado, '')) NOT IN ('cancelada','cancelado','anulada','anulado','eliminada','eliminado')
      GROUP BY solar_id HAVING COUNT(*) > 1
    );
  `)));
  relationships.push(checkCount('duplicate installment number per sale', sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count FROM (
      SELECT venta_id, numero_cuota FROM cuotas
      WHERE deleted_at IS NULL
      GROUP BY venta_id, numero_cuota HAVING COUNT(*) > 1
    );
  `)));

  financial.push(checkCount('ventas invalid/null money', sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count FROM ventas
    WHERE precio_venta IS NULL OR precio_venta < 0
       OR saldo_pendiente IS NULL OR saldo_pendiente < -0.009
       OR COALESCE(monto_inicial_requerido, 0) < -0.009
       OR COALESCE(monto_inicial_pagado, 0) < -0.009
       OR COALESCE(saldo_financiado, 0) < -0.009;
  `)));
  financial.push(checkCount('cuotas invalid/null money', sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count FROM cuotas
    WHERE capital_cuota IS NULL OR capital_cuota < -0.009
       OR interes_cuota IS NULL OR interes_cuota < -0.009
       OR monto_cuota IS NULL OR monto_cuota < -0.009
       OR monto_pagado IS NULL OR monto_pagado < -0.009
       OR COALESCE(capital_pagado, 0) < -0.009
       OR COALESCE(interes_pagado, 0) < -0.009;
  `)));
  financial.push(checkCount('pagos invalid/null money', sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count FROM pagos WHERE monto_pagado IS NULL OR monto_pagado < -0.009;
  `)));

  for (const [table, allowed] of Object.entries(validStatuses)) {
    const column = table === 'pagos' ? 'tipo_pago' : 'estado';
    statusCounts[table] = Object.fromEntries(
      sqliteRows(sqlitePath, `SELECT COALESCE(${column}, '') AS status, COUNT(*) AS count FROM ${table} GROUP BY ${column};`)
        .map((row) => [stringValue(row.status) ?? '', numberValue(row.count) ?? 0]),
    );
    const invalid = sqliteCount(sqlitePath, `
      SELECT COUNT(*) AS count FROM ${table}
      WHERE ${column} IS NULL OR LOWER(TRIM(${column})) NOT IN (${[...allowed].map((status) => `'${status}'`).join(',')});
    `);
    financial.push(checkCount(`${table}.${column} invalid status`, invalid));
  }

  const businessConfig = sqliteRows(sqlitePath, 'SELECT clave FROM configuracion ORDER BY clave;')
    .map((row) => {
      const key = stringValue(row.clave) ?? '';
      const classification = classifyBusinessConfigKey(key);
      return { key, classification, migrated: classification === 'CLOUD_BUSINESS' };
    });
  const unknownConfig = businessConfig.filter((entry) => entry.classification === 'UNKNOWN').length;
  if (unknownConfig > 0) {
    messages.push(`Unknown configuracion keys found: ${unknownConfig}`);
  }

  const integrityRepairable = integrity.some((line) => line.includes('missing from index'));
  const integrityOk = integrity.length === 1 && integrity[0] === 'ok';
  const quickOk = quickCheck.length === 1 && quickCheck[0] === 'ok';
  if (!integrityOk && !integrityRepairable) {
    messages.push(`SQLite integrity_check failed: ${integrity.join('; ')}`);
  }
  if (!quickOk && !integrityRepairable) {
    messages.push(`SQLite quick_check failed: ${quickCheck.join('; ')}`);
  }

  const blockingChecks = [...syncIdentity, ...relationships, ...financial].filter((check) => check.status === 'BLOCKING');
  messages.push(...blockingChecks.map((check) => check.message));

  const status: Severity = messages.length > 0
    ? 'BLOCKING'
    : integrityRepairable && !integrityOk
      ? 'REPAIRABLE_ON_WORKING_COPY'
      : 'PASS';

  return {
    status,
    userVersion: sqliteCount(sqlitePath, 'PRAGMA user_version;'),
    tableCount: sqliteCount(sqlitePath, "SELECT COUNT(*) AS count FROM sqlite_master WHERE type='table';"),
    integrity,
    quickCheck,
    tableCounts,
    activeCounts,
    deletedCounts,
    statusCounts,
    syncIdentity,
    relationships,
    financial,
    businessConfig,
    messages,
  };
}

export function repairWorkingCopy(sqlitePath: string, precheck: PrecheckReport): string[] {
  if (!precheck.integrity.some((line) => line.includes('missing from index'))) {
    return [];
  }
  execFileSync('sqlite3', [sqlitePath, 'REINDEX; PRAGMA integrity_check;'], {
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  return ['REINDEX on working copy'];
}

export function readSqliteBundle(sqlitePath: string): TableBundle {
  return Object.fromEntries(
    businessTables.map((table) => [
      table,
      sqliteRows(sqlitePath, `SELECT * FROM ${table} ORDER BY 1;`),
    ]),
  );
}

export function normalizeActiveSaleBalances(bundle: TableBundle): FinancialNormalizationReport {
  const sales = bundle.ventas ?? [];
  const installments = bundle.cuotas ?? [];
  const installmentsBySale = new Map<number, Row[]>();
  for (const installment of installments) {
    const saleId = intValue(installment.venta_id);
    if (saleId === null) continue;
    const saleInstallments = installmentsBySale.get(saleId) ?? [];
    saleInstallments.push(installment);
    installmentsBySale.set(saleId, saleInstallments);
  }

  const entries: FinancialNormalizationEntry[] = [];
  const messages: string[] = [];
  let affectedActiveSales = 0;
  let normalizedSales = 0;
  let unexplainedSales = 0;
  let positiveDeltas = 0;
  let negativeDeltas = 0;
  let minDeltaCents = 0;
  let maxDeltaCents = 0;
  let sumAbsoluteDeltaCents = 0;

  for (const sale of sales) {
    if (text(sale.deleted_at)) continue;
    const status = requiredText(sale.estado, '').toLowerCase();
    if (!['apartado', 'inicial_incompleto', 'activa'].includes(status)) continue;

    const saleId = intValue(sale.id);
    if (saleId === null) continue;
    const saleInstallments = installmentsBySale.get(saleId) ?? [];
    const eligibleInstallments = saleInstallments
      .filter((installment) => {
        if (text(installment.deleted_at)) return false;
        return requiredText(installment.estado, '').toLowerCase() !== 'ajustada';
      })
      .sort((a, b) => (intValue(a.numero_cuota) ?? 0) - (intValue(b.numero_cuota) ?? 0));

    const saleBalanceCents = moneyCents(sale.saldo_pendiente);
    const remainingCents = eligibleInstallments.reduce((sum, installment) => {
      const remaining = moneyCents(installment.capital_cuota) - moneyCents(installment.capital_pagado);
      return sum + Math.max(remaining, 0);
    }, 0);
    const deltaCents = saleBalanceCents - remainingCents;
    if (Math.abs(deltaCents) <= 1) continue;

    affectedActiveSales += 1;
    if (deltaCents > 0) positiveDeltas += 1;
    if (deltaCents < 0) negativeDeltas += 1;
    minDeltaCents = affectedActiveSales === 1 ? deltaCents : Math.min(minDeltaCents, deltaCents);
    maxDeltaCents = affectedActiveSales === 1 ? deltaCents : Math.max(maxDeltaCents, deltaCents);
    sumAbsoluteDeltaCents += Math.abs(deltaCents);

    const adjustedInstallment = [...eligibleInstallments]
      .reverse()
      .find((installment) => {
        const status = requiredText(installment.estado, '').toLowerCase();
        if (status === 'pagada' || status === 'cancelada') return false;
        const principalCents = moneyCents(installment.capital_cuota);
        const paidPrincipalCents = moneyCents(installment.capital_pagado);
        return principalCents + deltaCents >= paidPrincipalCents;
      });
    if (!adjustedInstallment) {
      unexplainedSales += 1;
      messages.push(`No eligible installment for sale residual: saleHash=${hashAuditKey(requiredText(sale.sync_id, `sale-${sale.id}`))}`);
      entries.push({
        saleHash: hashAuditKey(requiredText(sale.sync_id, `sale-${sale.id}`)),
        classification: 'UNEXPLAINED',
        action: 'NONE',
        installmentCount: eligibleInstallments.length,
        beforeRemainingPrincipal: centsString(remainingCents),
        saleBalance: centsString(saleBalanceCents),
        delta: centsString(deltaCents),
      });
      continue;
    }

    const principalBeforeCents = moneyCents(adjustedInstallment.capital_cuota);
    const totalBeforeCents = moneyCents(adjustedInstallment.monto_cuota);
    const principalAfterCents = principalBeforeCents + deltaCents;
    adjustedInstallment.capital_cuota = centsString(principalAfterCents);
    adjustedInstallment.monto_cuota = centsString(totalBeforeCents + deltaCents);
    adjustedInstallment.raw = {
      ...(raw(adjustedInstallment) as Record<string, unknown>),
      migration_normalization: {
        policy: 'PRESERVE_SALE_BALANCE_ADJUST_FINAL_ELIGIBLE_INSTALLMENT',
        delta: centsString(deltaCents),
      },
    };
    normalizedSales += 1;
    entries.push({
      saleHash: hashAuditKey(requiredText(sale.sync_id, `sale-${sale.id}`)),
      classification: 'ROUNDING_RESIDUAL',
      action: 'ADJUST_FINAL_ELIGIBLE_INSTALLMENT_PRINCIPAL',
      installmentCount: eligibleInstallments.length,
      beforeRemainingPrincipal: centsString(remainingCents),
      saleBalance: centsString(saleBalanceCents),
      delta: centsString(deltaCents),
      adjustedInstallmentHash: hashAuditKey(requiredText(adjustedInstallment.sync_id, `installment-${adjustedInstallment.id}`)),
      adjustedInstallmentNumber: intValue(adjustedInstallment.numero_cuota),
      principalBefore: centsString(principalBeforeCents),
      principalAfter: centsString(principalAfterCents),
    });
  }

  if (unexplainedSales > 0) {
    messages.push(`Unexplained active sale balance residuals: ${unexplainedSales}`);
  }

  return {
    status: unexplainedSales === 0 ? 'PASS' : 'BLOCKING',
    policy: 'PRESERVE_SALE_BALANCE_ADJUST_FINAL_ELIGIBLE_INSTALLMENT',
    affectedActiveSales,
    normalizedSales,
    unexplainedSales,
    positiveDeltas,
    negativeDeltas,
    minDelta: centsString(minDeltaCents),
    maxDelta: centsString(maxDeltaCents),
    sumAbsoluteDelta: centsString(sumAbsoluteDeltaCents),
    classifications: {
      ROUNDING_RESIDUAL: normalizedSales,
      UNEXPLAINED: unexplainedSales,
    },
    entries,
    messages,
  };
}

export async function importBundle(
  prisma: PrismaClient,
  bundle: TableBundle,
  options: Pick<MigrationCliOptions, 'companyTenantKey' | 'companyName'>,
): Promise<ImportReport> {
  const companyId = deterministicUuid('company', options.companyTenantKey);
  const company = await prisma.company.upsert({
    where: { tenantKey: options.companyTenantKey },
    update: { name: options.companyName, active: true },
    create: {
      id: companyId,
      tenantKey: options.companyTenantKey,
      name: options.companyName,
      active: true,
    },
  });

  const clients = bundle.clientes ?? [];
  const sellers = bundle.vendedores ?? [];
  const lots = bundle.solares ?? [];
  const users = bundle.usuarios ?? [];
  const roles = bundle.roles ?? [];
  const permissions = bundle.permisos ?? [];
  const userRoles = bundle.user_roles ?? [];
  const rolePermissions = bundle.role_permissions ?? [];
  const companyProfiles = bundle.company_profiles ?? [];
  const companyInfo = bundle.informacion_empresa ?? [];
  const financialRows = bundle.parametros_financieros ?? [];
  const configRows = bundle.configuracion ?? [];
  const sales = bundle.ventas ?? [];
  const installments = bundle.cuotas ?? [];
  const payments = bundle.pagos ?? [];

  const clientIds = new Map<number, string>();
  const sellerIds = new Map<number, string>();
  const lotIds = new Map<number, string>();
  const userIds = new Map<number, string>();
  const roleIds = new Map<number, string>();
  const permissionIds = new Map<number, string>();
  const saleIds = new Map<number, string>();
  const installmentIds = new Map<number, string>();

  for (const row of clients) {
    const syncId = requiredText(row.sync_id, `client-${row.id}`);
    const id = deterministicUuid('client', syncId);
    await prisma.client.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        name: requiredText(row.nombre, `Cliente ${row.id}`),
        document: text(row.cedula),
        phone: text(row.telefono),
        address: text(row.direccion),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    clientIds.set(Number(row.id), id);
  }

  for (const row of sellers) {
    const syncId = requiredText(row.sync_id, `seller-${row.id}`);
    const id = deterministicUuid('seller', syncId);
    await prisma.seller.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        name: requiredText(row.nombre, `Vendedor ${row.id}`),
        document: text(row.cedula),
        phone: text(row.telefono),
        active: date(row.deleted_at) === null,
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    sellerIds.set(Number(row.id), id);
  }

  for (const row of lots) {
    const syncId = requiredText(row.sync_id, `lot-${row.id}`);
    const id = deterministicUuid('lot', syncId);
    await prisma.lot.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        block: text(row.manzana_numero),
        number: text(row.solar_numero),
        area: normalizeMoney(row.metros_cuadrados),
        price: normalizeMoney(row.precio_por_metro),
        status: text(row.estado),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    lotIds.set(Number(row.id), id);
  }

  for (const row of users) {
    const syncId = requiredText(row.sync_id, `user-${row.id}`);
    const id = deterministicUuid('user', syncId);
    await prisma.user.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        email: requiredText(row.email, `local-user-${row.id}@migration.invalid`),
        name: requiredText(row.nombre, `Usuario ${row.id}`),
        passwordHash: requiredText(row.password_hash, 'migration-placeholder-password-hash'),
        role: userRole(row.rol),
        localRole: text(row.rol),
        phone: text(row.telefono),
        active: boolValue(row.activo),
        passwordResetRequired: boolValue(row.password_reset_required, false),
        passwordUpdatedAt: date(row.password_updated_at),
        remoteAuthId: text(row.remote_auth_id),
        authSource: text(row.auth_source),
        lastOnlineLoginAt: date(row.last_online_login_at),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    userIds.set(Number(row.id), id);
  }

  for (const row of roles) {
    const syncId = text(row.sync_id);
    const code = requiredText(row.code, `role-${row.id}`);
    const id = deterministicUuid('role', syncId ?? code);
    await prisma.businessRole.upsert({
      where: { companyId_code: { companyId: company.id, code } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        code,
        name: requiredText(row.name, code),
        description: text(row.description),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    roleIds.set(Number(row.id), id);
  }

  for (const row of permissions) {
    const syncId = requiredText(row.sync_id, `permission-${row.id}`);
    const id = deterministicUuid('permission', syncId);
    const localUserId = intValue(row.usuario_id);
    const userId = localUserId === null ? null : userIds.get(localUserId) ?? null;
    await prisma.permission.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        userId,
        module: requiredText(row.modulo, `module-${row.id}`),
        actions: actionsJson(row.acciones),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    permissionIds.set(Number(row.id), id);
  }

  for (const row of userRoles) {
    const userId = userIds.get(Number(row.user_id));
    const roleId = roleIds.get(Number(row.role_id));
    if (!userId || !roleId) continue;
    const syncId = text(row.sync_id);
    await prisma.businessUserRole.upsert({
      where: { companyId_userId_roleId: { companyId: company.id, userId, roleId } },
      update: {},
      create: {
        id: deterministicUuid('user_role', syncId ?? `${userId}:${roleId}`),
        companyId: company.id,
        userId,
        roleId,
        syncId,
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
  }

  for (const row of rolePermissions) {
    const roleId = roleIds.get(Number(row.role_id));
    const permissionId = permissionIds.get(Number(row.permission_id));
    if (!roleId || !permissionId) continue;
    const syncId = text(row.sync_id);
    await prisma.businessRolePermission.upsert({
      where: { companyId_roleId_permissionId: { companyId: company.id, roleId, permissionId } },
      update: {},
      create: {
        id: deterministicUuid('role_permission', syncId ?? `${roleId}:${permissionId}`),
        companyId: company.id,
        roleId,
        permissionId,
        syncId,
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
  }

  const profile = companyProfiles[0] ?? companyInfo[0];
  if (profile) {
    await prisma.companyProfile.upsert({
      where: { companyId: company.id },
      update: {},
      create: {
        id: deterministicUuid('company_profile', text(profile.sync_id) ?? company.id),
        companyId: company.id,
        syncId: text(profile.sync_id),
        name: requiredText(profile.name ?? profile.nombre, company.name),
        phone: text(profile.phone ?? profile.telefono),
        address: text(profile.address ?? profile.direccion),
        logoBase64: text(profile.logo_base64),
        logoLocalPath: text(profile.local_path),
        logoRemoteUrl: text(profile.remote_url),
        logoUploadStatus: text(profile.upload_status),
        deletedAt: date(profile.deleted_at),
        version: intValue(profile.version) ?? 1,
        raw: raw(profile),
      },
    });
  }

  const config = new Map(configRows.map((row) => [requiredText(row.clave, ''), text(row.valor)]));
  const financial = financialRows[0];
  await prisma.financialParameters.upsert({
    where: { companyId: company.id },
    update: {},
    create: {
      id: deterministicUuid('financial_parameters', company.id),
      companyId: company.id,
      syncId: financial ? text(financial.sync_id) : null,
      initialPercentage: normalizeMoney(financial?.inicial_porcentaje ?? config.get('sale_default_down_payment_percentage')),
      monthlyInterestRate: normalizeMoney(financial?.interes_mensual ?? config.get('sale_default_monthly_interest')),
      installmentCount: intValue(financial?.cantidad_cuotas ?? config.get('sale_default_installment_count')),
      currencySymbol: text(financial?.simbolo_moneda ?? config.get('currency_symbol')),
      decimalPlaces: intValue(financial?.lugares_decimales) ?? 2,
      deletedAt: financial ? date(financial.deleted_at) : null,
      version: intValue(financial?.version) ?? 1,
      raw: financial ? raw(financial) : { source: 'configuracion' },
    },
  });

  for (const row of configRows) {
    const key = requiredText(row.clave, '');
    if (classifyBusinessConfigKey(key) !== 'CLOUD_BUSINESS') continue;
    await prisma.businessConfiguration.upsert({
      where: { companyId_key: { companyId: company.id, key } },
      update: {},
      create: {
        id: deterministicUuid('business_config', `${company.id}:${key}`),
        companyId: company.id,
        key,
        value: text(row.valor),
        raw: raw(row),
      },
    });
  }

  const clientSync = syncLookup(clients);
  const sellerSync = syncLookup(sellers);
  const lotSync = syncLookup(lots);
  const userSync = syncLookup(users);
  const saleSync = syncLookup(sales);
  const installmentSync = syncLookup(installments);

  for (const row of sales) {
    const syncId = requiredText(row.sync_id, `sale-${row.id}`);
    const id = deterministicUuid('sale', syncId);
    await prisma.sale.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        clientId: mapId(clientIds, row.cliente_id),
        lotId: mapId(lotIds, row.solar_id),
        sellerId: mapId(sellerIds, row.vendedor_id),
        operatorUserId: mapId(userIds, row.usuario_id),
        clientSyncId: clientSync.get(Number(row.cliente_id)) ?? null,
        lotSyncId: lotSync.get(Number(row.solar_id)) ?? null,
        sellerSyncId: sellerSync.get(Number(row.vendedor_id)) ?? null,
        operatorUserSyncId: userSync.get(Number(row.usuario_id)) ?? null,
        saleDate: date(row.fecha_venta),
        status: text(row.estado),
        total: normalizeMoney(row.precio_venta),
        initialPercentage: normalizeMoney(row.inicial_porcentaje),
        initialRequiredAmount: normalizeMoney(row.monto_inicial_requerido ?? row.inicial_monto),
        initialPaid: normalizeMoney(row.monto_inicial_pagado),
        initialPendingAmount: normalizeMoney(row.monto_inicial_pendiente),
        reservationMinimumAmount: normalizeMoney(row.monto_apartado_minimo),
        reservationPaidAmount: normalizeMoney(row.monto_apartado_pagado),
        initialPaymentDeadline: date(row.fecha_limite_inicial),
        activationDate: date(row.fecha_activacion),
        financedBalance: normalizeMoney(row.saldo_financiado),
        monthlyInterestRate: normalizeMoney(row.interes_mensual),
        installmentCount: intValue(row.cantidad_cuotas),
        balance: normalizeMoney(row.saldo_pendiente),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    saleIds.set(Number(row.id), id);
  }

  for (const row of installments) {
    const syncId = requiredText(row.sync_id, `installment-${row.id}`);
    const id = deterministicUuid('installment', syncId);
    await prisma.installment.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id,
        companyId: company.id,
        syncId,
        saleId: mapId(saleIds, row.venta_id),
        saleSyncId: saleSync.get(Number(row.venta_id)) ?? null,
        installmentNumber: intValue(row.numero_cuota),
        dueDate: date(row.fecha_vencimiento),
        openingBalance: normalizeMoney(row.saldo_inicial),
        principalAmount: normalizeMoney(row.capital_cuota),
        interestAmount: normalizeMoney(row.interes_cuota),
        totalAmount: normalizeMoney(row.monto_cuota),
        paidAmount: normalizeMoney(row.monto_pagado),
        paidPrincipalAmount: normalizeMoney(row.capital_pagado),
        paidInterestAmount: normalizeMoney(row.interes_pagado),
        endingBalance: normalizeMoney(row.saldo_final),
        status: text(row.estado),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
    installmentIds.set(Number(row.id), id);
  }

  for (const row of payments) {
    const syncId = requiredText(row.sync_id, `payment-${row.id}`);
    await prisma.payment.upsert({
      where: { companyId_syncId: { companyId: company.id, syncId } },
      update: {},
      create: {
        id: deterministicUuid('payment', syncId),
        companyId: company.id,
        syncId,
        saleId: mapId(saleIds, row.venta_id),
        clientId: mapId(clientIds, row.cliente_id),
        installmentId: mapId(installmentIds, row.cuota_id),
        receivedByUserId: mapId(userIds, row.usuario_id),
        saleSyncId: saleSync.get(Number(row.venta_id)) ?? null,
        clientSyncId: clientSync.get(Number(row.cliente_id)) ?? null,
        installmentSyncId: installmentSync.get(Number(row.cuota_id)) ?? null,
        receivedByUserSyncId: userSync.get(Number(row.usuario_id)) ?? null,
        paidAt: date(row.fecha_pago),
        amount: normalizeMoney(row.monto_pagado),
        method: text(row.metodo_pago),
        paymentType: text(row.tipo_pago),
        reference: text(row.referencia),
        yearToPay: intValue(row.ano_a_pagar),
        deletedAt: date(row.deleted_at),
        version: intValue(row.version) ?? 1,
        raw: raw(row),
      },
    });
  }

  return {
    status: 'PASS',
    companyId: company.id,
    counts: await pgCounts(prisma, company.id),
  };
}

export async function reconcile(
  prisma: PrismaClient,
  bundle: TableBundle,
  companyId: string,
): Promise<ReconciliationReport> {
  const counts: Record<string, ReconciliationEntry> = {};
  const sourceCounts: Record<string, number> = {
    clientes: bundle.clientes.length,
    vendedores: bundle.vendedores.length,
    solares: bundle.solares.length,
    ventas: bundle.ventas.length,
    cuotas: bundle.cuotas.length,
    pagos: bundle.pagos.length,
    usuarios: bundle.usuarios.length,
    roles: bundle.roles.length,
    permissions: bundle.permisos.length,
    user_roles: bundle.user_roles.length,
    role_permissions: bundle.role_permissions.length,
    company_profile: (bundle.company_profiles.length || bundle.informacion_empresa.length) > 0 ? 1 : 0,
    financial_parameters: 1,
    business_configuration: bundle.configuracion.filter((row) => classifyBusinessConfigKey(requiredText(row.clave, '')) === 'CLOUD_BUSINESS').length,
  };
  const targetCounts = await pgCounts(prisma, companyId);
  for (const [key, sqlite] of Object.entries(sourceCounts)) {
    counts[key] = compareCount(sqlite, targetCounts[key] ?? 0);
  }

  const statuses: Record<string, Record<string, ReconciliationEntry>> = {};
  for (const table of ['solares', 'ventas', 'cuotas'] as const) {
    statuses[table] = await compareStatus(prisma, companyId, bundle[table], table, 'estado');
  }
  statuses.pagos = await compareStatus(prisma, companyId, bundle.pagos, 'pagos', 'tipo_pago');

  const softDeletes: Record<string, ReconciliationEntry> = {};
  for (const table of ['clientes', 'vendedores', 'solares', 'ventas', 'cuotas', 'pagos', 'usuarios'] as const) {
    const sqlite = bundle[table].filter((row) => text(row.deleted_at)).length;
    const postgres = await pgDeletedCount(prisma, companyId, table);
    softDeletes[table] = compareCount(sqlite, postgres);
  }

  const financial = await reconcileMoney(prisma, bundle, companyId);
  const activeSaleBalances = await reconcileActiveSaleBalances(prisma, companyId);
  const messages: string[] = [];
  for (const [key, value] of Object.entries(counts)) {
    if (!value.passed) messages.push(`Count mismatch for ${key}: sqlite=${value.sqlite} postgres=${value.postgres}`);
  }
  for (const [key, value] of Object.entries(financial)) {
    if (!value.passed) messages.push(`Financial mismatch for ${key}: sqlite=${value.sqliteNormalized} postgres=${value.postgres}`);
  }
  if (activeSaleBalances.status !== 'PASS') {
    messages.push(`Active sale balance mismatch: count=${activeSaleBalances.mismatches} maxDelta=${activeSaleBalances.maxDelta}`);
  }

  return {
    status: messages.length === 0 ? 'PASS' : 'BLOCKING',
    counts,
    statuses,
    softDeletes,
    relationships: [
      checkCount('PostgreSQL sales missing client relation', await rawPgCount(prisma, 'SELECT COUNT(*)::int AS count FROM "Sale" WHERE "companyId"=$1 AND "clientSyncId" IS NOT NULL AND "clientId" IS NULL', companyId)),
      checkCount('PostgreSQL payments missing sale relation', await rawPgCount(prisma, 'SELECT COUNT(*)::int AS count FROM "Payment" WHERE "companyId"=$1 AND "saleSyncId" IS NOT NULL AND "saleId" IS NULL', companyId)),
      checkCount('PostgreSQL installments missing sale relation', await rawPgCount(prisma, 'SELECT COUNT(*)::int AS count FROM "Installment" WHERE "companyId"=$1 AND "saleSyncId" IS NOT NULL AND "saleId" IS NULL', companyId)),
    ],
    syncIdentities: [
      checkCount('PostgreSQL duplicate client syncId', await duplicatePgSyncCount(prisma, companyId, 'Client')),
      checkCount('PostgreSQL duplicate sale syncId', await duplicatePgSyncCount(prisma, companyId, 'Sale')),
      checkCount('PostgreSQL duplicate payment syncId', await duplicatePgSyncCount(prisma, companyId, 'Payment')),
    ],
    financial,
    activeSaleBalances,
    tolerance: Number(moneyTolerance),
    messages,
  };
}

export function deploySchema(options: Pick<MigrationCliOptions, 'target' | 'allowSqlFallback'>): SchemaDeployReport {
  const messages: string[] = [];
  const env = { ...process.env, DATABASE_URL: options.target ?? process.env.DATABASE_URL ?? '' };
  const prismaResult = spawnSync(process.platform === 'win32' ? 'npx.cmd' : 'npx', ['prisma', 'migrate', 'deploy'], {
    cwd: resolve(__dirname, '..', '..'),
    env,
    encoding: 'utf8',
  });
  if (prismaResult.status === 0) {
    return { status: 'PASS', prismaMigrateDeploy: 'PASS', fallbackUsed: false, messages };
  }

  messages.push(`prisma migrate deploy failed: ${(prismaResult.stderr || prismaResult.stdout || 'no output').trim()}`);
  if (!options.allowSqlFallback) {
    return { status: 'BLOCKING', prismaMigrateDeploy: 'FAIL', fallbackUsed: false, messages };
  }
  const fallback = deploySchemaWithPsqlFallback(env.DATABASE_URL);
  messages.push(...fallback.messages);
  return {
    status: fallback.status,
    prismaMigrateDeploy: 'FAIL',
    fallbackUsed: true,
    fallbackStatus: fallback.status === 'PASS' ? 'PASS' : 'FAIL',
    messages,
  };
}

export function deploySchemaWithPsqlFallback(databaseUrl: string): Pick<SchemaDeployReport, 'status' | 'messages'> {
  const migrationsRoot = resolve(__dirname, '..', '..', 'prisma', 'migrations');
  const migrations = readdirSync(migrationsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort();
  const messages: string[] = [];
  const createHistory = `
    CREATE TABLE IF NOT EXISTS "_prisma_migrations" (
      "id" VARCHAR(36) PRIMARY KEY NOT NULL,
      "checksum" VARCHAR(64) NOT NULL,
      "finished_at" TIMESTAMPTZ,
      "migration_name" VARCHAR(255) NOT NULL,
      "logs" TEXT,
      "rolled_back_at" TIMESTAMPTZ,
      "started_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
      "applied_steps_count" INTEGER NOT NULL DEFAULT 0
    );
  `;
  const init = runPsql(databaseUrl, createHistory);
  if (init.status !== 0) {
    return { status: 'BLOCKING', messages: [`psql fallback failed to create migration history: ${init.stderr}`] };
  }
  for (const migrationName of migrations) {
    const sqlPath = join(migrationsRoot, migrationName, 'migration.sql');
    const sql = readFileSync(sqlPath, 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const alreadyApplied = runPsql(databaseUrl, `SELECT checksum FROM "_prisma_migrations" WHERE migration_name='${escapeSql(migrationName)}';`);
    if (alreadyApplied.stdout.includes(checksum)) {
      messages.push(`migration already applied: ${migrationName}`);
      continue;
    }
    if (alreadyApplied.stdout.trim().length > 0) {
      return { status: 'BLOCKING', messages: [`Migration history checksum mismatch for ${migrationName}`] };
    }
    const result = runPsql(databaseUrl, `BEGIN;\n${sql}\nINSERT INTO "_prisma_migrations" ("id","checksum","finished_at","migration_name","logs","rolled_back_at","started_at","applied_steps_count") VALUES ('${randomUUID()}','${checksum}',now(),'${escapeSql(migrationName)}',NULL,NULL,now(),1);\nCOMMIT;`);
    if (result.status !== 0) {
      return { status: 'BLOCKING', messages: [`psql fallback failed for ${migrationName}: ${result.stderr}`] };
    }
    messages.push(`migration applied by fallback: ${migrationName}`);
  }
  return { status: 'PASS', messages };
}

function runPsql(databaseUrl: string, sql: string) {
  return spawnSync('psql', [databaseUrl, '-v', 'ON_ERROR_STOP=1', '-X', '-q'], {
    input: sql,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
}

async function pgCounts(prisma: PrismaClient, companyId: string): Promise<Record<string, number>> {
  return {
    clientes: await prisma.client.count({ where: { companyId } }),
    vendedores: await prisma.seller.count({ where: { companyId } }),
    solares: await prisma.lot.count({ where: { companyId } }),
    ventas: await prisma.sale.count({ where: { companyId } }),
    cuotas: await prisma.installment.count({ where: { companyId } }),
    pagos: await prisma.payment.count({ where: { companyId } }),
    usuarios: await prisma.user.count({ where: { companyId } }),
    roles: await prisma.businessRole.count({ where: { companyId } }),
    permissions: await prisma.permission.count({ where: { companyId } }),
    user_roles: await prisma.businessUserRole.count({ where: { companyId } }),
    role_permissions: await prisma.businessRolePermission.count({ where: { companyId } }),
    company_profile: await prisma.companyProfile.count({ where: { companyId } }),
    financial_parameters: await prisma.financialParameters.count({ where: { companyId } }),
    business_configuration: await prisma.businessConfiguration.count({ where: { companyId } }),
  };
}

async function reconcileMoney(
  prisma: PrismaClient,
  bundle: TableBundle,
  companyId: string,
): Promise<Record<string, MoneyReconciliationEntry>> {
  const sqlite = {
    sale_totals: sumNormalizedMoney(bundle.ventas, 'precio_venta'),
    payment_totals: sumNormalizedMoney(bundle.pagos, 'monto_pagado'),
    sale_balances: sumNormalizedMoney(bundle.ventas, 'saldo_pendiente'),
    principal_paid: sumNormalizedMoney(bundle.cuotas, 'capital_pagado'),
    interest_paid: sumNormalizedMoney(bundle.cuotas, 'interes_pagado'),
    remaining_installment_principal: bundle.cuotas.reduce((sum, row) => {
      if (text(row.deleted_at)) return sum;
      if (requiredText(row.estado, '').toLowerCase() === 'ajustada') return sum;
      const remaining = normalizeMoney(row.capital_cuota).minus(normalizeMoney(row.capital_pagado));
      return sum.plus(Prisma.Decimal.max(remaining, 0));
    }, new Prisma.Decimal(0)),
  };
  const sqliteRaw = {
    sale_totals: rawMoneySum(bundle.ventas, 'precio_venta'),
    payment_totals: rawMoneySum(bundle.pagos, 'monto_pagado'),
    sale_balances: rawMoneySum(bundle.ventas, 'saldo_pendiente'),
    principal_paid: rawMoneySum(bundle.cuotas, 'capital_pagado'),
    interest_paid: rawMoneySum(bundle.cuotas, 'interes_pagado'),
    remaining_installment_principal: bundle.cuotas.reduce((sum, row) => {
      if (text(row.deleted_at)) return sum;
      if (requiredText(row.estado, '').toLowerCase() === 'ajustada') return sum;
      return sum + Math.max((numberValue(row.capital_cuota) ?? 0) - (numberValue(row.capital_pagado) ?? 0), 0);
    }, 0),
  };
  const pgRows = await prisma.$queryRaw<Array<Record<string, string>>>`
    SELECT
      ROUND(COALESCE((SELECT SUM(total) FROM "Sale" WHERE "companyId" = ${companyId}), 0)::numeric, 2)::text AS sale_totals,
      ROUND(COALESCE((SELECT SUM(amount) FROM "Payment" WHERE "companyId" = ${companyId}), 0)::numeric, 2)::text AS payment_totals,
      ROUND(COALESCE((SELECT SUM(balance) FROM "Sale" WHERE "companyId" = ${companyId}), 0)::numeric, 2)::text AS sale_balances,
      ROUND(COALESCE((SELECT SUM("paidPrincipalAmount") FROM "Installment" WHERE "companyId" = ${companyId}), 0)::numeric, 2)::text AS principal_paid,
      ROUND(COALESCE((SELECT SUM("paidInterestAmount") FROM "Installment" WHERE "companyId" = ${companyId}), 0)::numeric, 2)::text AS interest_paid,
      ROUND(COALESCE((SELECT SUM(GREATEST("principalAmount" - "paidPrincipalAmount", 0)) FROM "Installment" WHERE "companyId" = ${companyId} AND "deletedAt" IS NULL AND LOWER(COALESCE(status, '')) <> 'ajustada'), 0)::numeric, 2)::text AS remaining_installment_principal
  `;
  const pg = pgRows[0];
  return Object.fromEntries(
    Object.entries(sqlite).map(([key, normalized]) => {
      const postgres = new Prisma.Decimal(pg[key] ?? 0);
      const delta = postgres.minus(normalized).abs();
      return [
        key,
        {
          sqliteRaw: normalizeMoney(sqliteRaw[key as keyof typeof sqliteRaw]).toFixed(2),
          sqliteNormalized: normalized.toFixed(2),
          postgres: postgres.toFixed(2),
          delta: delta.toFixed(2),
          passed: delta.lte(moneyTolerance),
        },
      ];
    }),
  );
}

async function reconcileActiveSaleBalances(
  prisma: PrismaClient,
  companyId: string,
): Promise<ActiveSaleBalanceReconciliation> {
  const rows = await prisma.$queryRaw<Array<{ checked: number; mismatches: number; max_delta: string }>>`
    WITH active_sales AS (
      SELECT
        s.id,
        s.balance,
        COALESCE(
          SUM(GREATEST(i."principalAmount" - i."paidPrincipalAmount", 0))
            FILTER (
              WHERE i."deletedAt" IS NULL
                AND LOWER(COALESCE(i.status, '')) <> 'ajustada'
            ),
          0
        )::numeric(14, 2) AS remaining_principal
      FROM "Sale" s
      LEFT JOIN "Installment" i ON i."saleId" = s.id
      WHERE s."companyId" = ${companyId}
        AND s."deletedAt" IS NULL
        AND LOWER(COALESCE(s.status, '')) IN ('apartado', 'inicial_incompleto', 'activa')
      GROUP BY s.id, s.balance
    )
    SELECT
      COUNT(*)::int AS checked,
      COUNT(*) FILTER (WHERE ABS(balance - remaining_principal) > ${activeSaleBalanceTolerance})::int AS mismatches,
      ROUND(COALESCE(MAX(ABS(balance - remaining_principal)), 0)::numeric, 2)::text AS max_delta
    FROM active_sales
  `;
  const row = rows[0] ?? { checked: 0, mismatches: 0, max_delta: '0.00' };
  const mismatches = Number(row.mismatches);
  return {
    status: mismatches === 0 ? 'PASS' : 'BLOCKING',
    checked: Number(row.checked),
    mismatches,
    maxDelta: new Prisma.Decimal(row.max_delta ?? 0).toFixed(2),
  };
}

async function compareStatus(
  prisma: PrismaClient,
  companyId: string,
  rows: Row[],
  table: 'solares' | 'ventas' | 'cuotas' | 'pagos',
  column: string,
): Promise<Record<string, ReconciliationEntry>> {
  const sqliteCounts = new Map<string, number>();
  for (const row of rows) {
    const key = requiredText(row[column], '');
    sqliteCounts.set(key, (sqliteCounts.get(key) ?? 0) + 1);
  }
  const model = {
    solares: '"Lot"',
    ventas: '"Sale"',
    cuotas: '"Installment"',
    pagos: '"Payment"',
  }[table];
  const pgColumn = table === 'pagos' ? '"paymentType"' : 'status';
  const pgRows = await prisma.$queryRawUnsafe<Array<{ key: string; count: number }>>(
    `SELECT COALESCE(${pgColumn}, '') AS key, COUNT(*)::int AS count FROM ${model} WHERE "companyId"=$1 GROUP BY ${pgColumn}`,
    companyId,
  );
  const pgCounts = new Map(pgRows.map((row) => [row.key, Number(row.count)]));
  const keys = new Set([...sqliteCounts.keys(), ...pgCounts.keys()]);
  return Object.fromEntries([...keys].map((key) => [key, compareCount(sqliteCounts.get(key) ?? 0, pgCounts.get(key) ?? 0)]));
}

async function pgDeletedCount(prisma: PrismaClient, companyId: string, table: string): Promise<number> {
  const model = {
    clientes: '"Client"',
    vendedores: '"Seller"',
    solares: '"Lot"',
    ventas: '"Sale"',
    cuotas: '"Installment"',
    pagos: '"Payment"',
    usuarios: '"User"',
  }[table];
  return rawPgCount(prisma, `SELECT COUNT(*)::int AS count FROM ${model} WHERE "companyId"=$1 AND "deletedAt" IS NOT NULL`, companyId);
}

async function duplicatePgSyncCount(prisma: PrismaClient, companyId: string, model: string): Promise<number> {
  return rawPgCount(prisma, `SELECT COUNT(*)::int AS count FROM (SELECT "syncId" FROM "${model}" WHERE "companyId"=$1 AND "syncId" IS NOT NULL GROUP BY "syncId" HAVING COUNT(*) > 1) t`, companyId);
}

async function rawPgCount(prisma: PrismaClient, sql: string, companyId: string): Promise<number> {
  const rows = await prisma.$queryRawUnsafe<Array<{ count: number }>>(sql, companyId);
  return Number(rows[0]?.count ?? 0);
}

function sqliteRows(sqlitePath: string, sql: string): Row[] {
  const output = execFileSync('sqlite3', ['-readonly', '-json', sqlitePath, sql], {
    encoding: 'utf8',
    maxBuffer: 128 * 1024 * 1024,
  }).trim();
  if (!output) return [];
  const parsed = JSON.parse(output) as Row[] | Row;
  return Array.isArray(parsed) ? parsed : [parsed];
}

function sqliteScalarRows(sqlitePath: string, sql: string): string[] {
  return execFileSync('sqlite3', ['-readonly', sqlitePath, sql], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  }).trim().split(/\r?\n/).filter(Boolean);
}

function sqliteCount(sqlitePath: string, sql: string): number {
  const rows = sqliteRows(sqlitePath, sql);
  const value = Object.values(rows[0] ?? { count: 0 })[0];
  return numberValue(value) ?? 0;
}

function orphanCount(sqlitePath: string, table: string, column: string, parent: string): number {
  if (!hasColumn(sqlitePath, table, column)) return 0;
  return sqliteCount(sqlitePath, `
    SELECT COUNT(*) AS count
    FROM ${table} child
    LEFT JOIN ${parent} parent ON parent.id = child.${column}
    WHERE child.${column} IS NOT NULL AND parent.id IS NULL;
  `);
}

function hasColumn(sqlitePath: string, table: string, column: string): boolean {
  return sqliteRows(sqlitePath, `PRAGMA table_info(${table});`).some((row) => row.name === column);
}

function checkCount(check: string, count: number): CheckResult {
  return {
    check,
    count,
    status: count === 0 ? 'PASS' : 'BLOCKING',
    message: count === 0 ? `${check}: PASS` : `${check}: ${count}`,
  };
}

function compareCount(sqlite: number, postgres: number): ReconciliationEntry {
  return { sqlite, postgres, delta: postgres - sqlite, passed: sqlite === postgres };
}

function rawMoneySum(rows: Row[], key: string): number {
  return rows.reduce((sum, row) => sum + (numberValue(row[key]) ?? 0), 0);
}

function text(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim();
  return trimmed.length > 0 ? trimmed : null;
}

function stringValue(value: unknown): string | null {
  return text(value);
}

function requiredText(value: unknown, fallback: string): string {
  return text(value) ?? fallback;
}

function numberValue(value: unknown): number | null {
  const raw = text(value);
  if (!raw) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : null;
}

function intValue(value: unknown): number | null {
  const numeric = numberValue(value);
  return numeric === null ? null : Math.trunc(numeric);
}

function boolValue(value: unknown, fallback = true): boolean {
  const numeric = numberValue(value);
  return numeric === null ? fallback : numeric !== 0;
}

function date(value: unknown): Date | null {
  const raw = text(value);
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function raw(row: Row): Prisma.InputJsonObject {
  return Object.fromEntries(Object.entries(row).filter(([, value]) => value !== undefined)) as Prisma.InputJsonObject;
}

function userRole(localRole: unknown): UserRole {
  const role = requiredText(localRole, '').toLowerCase();
  return role.includes('admin') || role.includes('owner') ? UserRole.OWNER : UserRole.TECH;
}

function actionsJson(value: unknown): Prisma.InputJsonValue {
  const rawValue = text(value);
  if (!rawValue) return [];
  try {
    return JSON.parse(rawValue) as Prisma.InputJsonValue;
  } catch {
    return rawValue.split(',').map((part) => part.trim()).filter(Boolean);
  }
}

function mapId(map: Map<number, string>, value: unknown): string | null {
  const id = intValue(value);
  return id === null ? null : map.get(id) ?? null;
}

function syncLookup(rows: Row[]): Map<number, string> {
  return new Map(rows.map((row) => [Number(row.id), requiredText(row.sync_id, '')]));
}

function sha256(path: string): string {
  return createHash('sha256').update(readFileSync(path)).digest('hex').toUpperCase();
}

function escapeSql(value: string): string {
  return value.replace(/'/g, "''");
}

function writeReports(report: MigrationReport, outputDir: string): void {
  mkdirSync(outputDir, { recursive: true });
  writeFileSync(join(outputDir, 'customer_migration_report.json'), JSON.stringify(report, null, 2));
  writeFileSync(join(outputDir, 'customer_migration_report.md'), renderMarkdownReport(report));
}

export function renderMarkdownReport(report: MigrationReport): string {
  const lines = [
    '# Customer SQLite Migration Report',
    '',
    `Final status: ${report.finalStatus}`,
    `Started at: ${report.startedAt}`,
    `Finished at: ${report.finishedAt ?? 'NOT FINISHED'}`,
    '',
    '## Source Safety',
    '',
    `Original: ${report.source.originalPath}`,
    `Original SHA256 before: ${report.source.originalSha256Before}`,
    `Original SHA256 after: ${report.source.originalSha256After ?? 'PENDING'}`,
    `Original unchanged: ${report.source.originalUnchanged === true ? 'YES' : 'NO/PENDING'}`,
    `Working copy: ${report.source.workingCopyPath}`,
    `Working copy SHA256 before repair: ${report.source.workingCopySha256BeforeRepair}`,
    `Working copy SHA256 after repair: ${report.source.workingCopySha256AfterRepair ?? 'NO REPAIR'}`,
    `Repair actions: ${report.source.repairActions.length === 0 ? 'NONE' : report.source.repairActions.join(', ')}`,
    '',
    'Sidecars:',
    ...report.source.sidecars.map((sidecar) => `- ${sidecar.suffix}: ${sidecar.exists ? `YES size=${sidecar.size}` : 'NO'}`),
    '',
    '## Precheck',
    '',
    `Status: ${report.precheck?.status ?? 'NOT RUN'}`,
    `User version: ${report.precheck?.userVersion ?? 'N/A'}`,
    '',
    '## Migration',
    '',
    '## Financial Normalization',
    '',
    `Policy: ${report.financialNormalization?.policy ?? 'NOT RUN'}`,
    `Affected active sales: ${report.financialNormalization?.affectedActiveSales ?? 'N/A'}`,
    `Normalized sales: ${report.financialNormalization?.normalizedSales ?? 'N/A'}`,
    `Unexplained sales: ${report.financialNormalization?.unexplainedSales ?? 'N/A'}`,
    `Delta range: ${report.financialNormalization ? `${report.financialNormalization.minDelta} to ${report.financialNormalization.maxDelta}` : 'N/A'}`,
    `Sum absolute delta: ${report.financialNormalization?.sumAbsoluteDelta ?? 'N/A'}`,
    '',
    `Status: ${report.migration?.status ?? 'NOT RUN'}`,
    '',
    '## Reconciliation',
    '',
    `Status: ${report.reconciliation?.status ?? 'NOT RUN'}`,
    `Active sale balance mismatches: ${report.reconciliation?.activeSaleBalances.mismatches ?? 'N/A'}`,
    `Active sale balance max delta: ${report.reconciliation?.activeSaleBalances.maxDelta ?? 'N/A'}`,
    '',
    'P0:',
    ...(report.p0.length === 0 ? ['- NONE'] : report.p0.map((item) => `- ${item}`)),
    '',
  ];
  return `${lines.join('\n')}\n`;
}
