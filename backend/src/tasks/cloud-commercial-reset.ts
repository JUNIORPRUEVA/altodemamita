import { PrismaClient } from '@prisma/client';
import { spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

type Mode = 'dry-run' | 'execute';

interface DeleteGroup {
  step: number;
  label: string;
  tables: string[];
}

interface BackupInfo {
  path: string;
  sizeBytes: number;
  createdAt: string;
}

interface TableCount {
  table: string;
  count: number;
}

interface ResetReport {
  mode: Mode;
  executed: boolean;
  timestamp: string;
  databaseHost: string;
  databaseName: string;
  keepTablesConfigured: string[];
  keepTablesExisting: TableCount[];
  deletePlanConfigured: DeleteGroup[];
  deletePlanResolved: DeleteGroup[];
  beforeCounts: TableCount[];
  afterCounts?: TableCount[];
  deletedRowsByTable?: TableCount[];
  backup?: BackupInfo;
  skippedMissingTables: string[];
  notes: string[];
}

const KEEP_TABLES: string[] = [
  'users',
  'roles',
  'permissions',
  'user_roles',
  'role_permissions',
  'company_profiles',
  'authorized_devices',
  '_prisma_migrations',
];

const DELETE_PLAN: DeleteGroup[] = [
  {
    step: 1,
    label: 'Pagos, asignaciones y detalles dependientes',
    tables: ['payment_allocations', 'payments', 'sale_details'],
  },
  {
    step: 2,
    label: 'Cuotas',
    tables: ['installments'],
  },
  {
    step: 3,
    label: 'Ventas y detalles comerciales',
    tables: ['sales'],
  },
  {
    step: 4,
    label: 'Clientes',
    tables: ['clients'],
  },
  {
    step: 5,
    label: 'Vendedores',
    tables: ['sellers'],
  },
  {
    step: 6,
    label: 'Lotes y productos comerciales',
    tables: ['lots', 'products'],
  },
  {
    step: 7,
    label: 'Logs/reportes/sync comercial',
    tables: [
      'sync_queue',
      'sync_events',
      'sync_event_logs',
      'sync_conflicts',
      'conflict_logs',
      'sync_conflict_logs',
      'commercial_reports',
      'sales_reports',
      'payment_reports',
    ],
  },
];

function nowIso(): string {
  return new Date().toISOString();
}

function parseMode(argv: string[]): Mode {
  const modeArg = argv.find((arg) => arg.startsWith('--mode='));
  const mode = modeArg?.split('=')[1]?.trim();
  if (mode === 'dry-run' || mode === 'execute') {
    return mode;
  }
  throw new Error('Debes indicar --mode=dry-run o --mode=execute');
}

function sanitizeFileStamp(value: string): string {
  return value.replace(/[:.]/g, '-');
}

function getDatabaseSummary(databaseUrl: string): {
  host: string;
  database: string;
} {
  const url = new URL(databaseUrl);
  return {
    host: url.host,
    database: url.pathname.replace(/^\//, '') || '(unknown)',
  };
}

function quoteIdentifier(identifier: string): string {
  return `"${identifier.replace(/"/g, '""')}"`;
}

async function runPgDump(backupPath: string, databaseUrl: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const args = [
      '--dbname',
      databaseUrl,
      '--format=plain',
      '--no-owner',
      '--no-privileges',
      '--file',
      backupPath,
    ];

    const child = spawn('pg_dump', args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
    });

    let stderr = '';
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString();
    });

    child.on('error', (error) => {
      reject(
        new Error(
          `No se pudo ejecutar pg_dump (${error.message}). Verifica que PostgreSQL tools este instalado y en PATH.`,
        ),
      );
    });

    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`pg_dump finalizo con codigo ${code}. ${stderr.trim()}`));
        return;
      }
      resolve();
    });
  });
}

function ensureDirectory(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

async function fetchExistingTables(prisma: PrismaClient): Promise<Set<string>> {
  const rows = await prisma.$queryRaw<Array<{ table_name: string }>>`
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
  `;

  return new Set(rows.map((row) => row.table_name));
}

async function countTables(
  prisma: PrismaClient,
  tables: string[],
): Promise<TableCount[]> {
  const result: TableCount[] = [];

  for (const table of tables) {
    const sql = `SELECT COUNT(*)::bigint AS count FROM ${quoteIdentifier(table)}`;
    const rows = await prisma.$queryRawUnsafe<Array<{ count: bigint | number | string }>>(sql);
    const rawCount = rows[0]?.count ?? 0;
    result.push({ table, count: Number(rawCount) });
  }

  return result;
}

function resolveDeletePlan(existingTables: Set<string>): {
  resolved: DeleteGroup[];
  missing: string[];
  orderedTables: string[];
} {
  const missing: string[] = [];
  const resolved = DELETE_PLAN.map((group) => {
    const tables = group.tables.filter((table) => {
      const exists = existingTables.has(table);
      if (!exists) {
        missing.push(table);
      }
      return exists;
    });

    return {
      ...group,
      tables,
    };
  }).filter((group) => group.tables.length > 0);

  const orderedTables = resolved.flatMap((group) => group.tables);

  return {
    resolved,
    missing,
    orderedTables,
  };
}

async function deleteCommercialTables(
  prisma: PrismaClient,
  orderedTables: string[],
): Promise<void> {
  await prisma.$transaction(async (tx) => {
    for (const table of orderedTables) {
      const sql = `DELETE FROM ${quoteIdentifier(table)}`;
      await tx.$executeRawUnsafe(sql);
    }
  });
}

function writeJsonReport(reportDir: string, mode: Mode, report: ResetReport): string {
  ensureDirectory(reportDir);
  const fileName = `cloud-commercial-reset-${mode}-${sanitizeFileStamp(report.timestamp)}.json`;
  const fullPath = path.join(reportDir, fileName);
  fs.writeFileSync(fullPath, JSON.stringify(report, null, 2), 'utf8');
  return fullPath;
}

async function main(): Promise<void> {
  const mode = parseMode(process.argv.slice(2));
  const databaseUrl = process.env.DATABASE_URL?.trim() ?? '';
  if (databaseUrl.length === 0) {
    throw new Error('DATABASE_URL es obligatorio.');
  }

  if (mode === 'execute' && process.env.CONFIRM_CLOUD_COMMERCIAL_RESET !== 'true') {
    throw new Error(
      'Ejecucion bloqueada: define CONFIRM_CLOUD_COMMERCIAL_RESET=true para continuar.',
    );
  }

  const summary = getDatabaseSummary(databaseUrl);
  const prisma = new PrismaClient();

  try {
    const existingTables = await fetchExistingTables(prisma);
    const existingKeepTables = KEEP_TABLES.filter((table) => existingTables.has(table));
    const { resolved, missing, orderedTables } = resolveDeletePlan(existingTables);

    const keepCounts = await countTables(prisma, existingKeepTables);
    const beforeCounts = await countTables(prisma, orderedTables);

    const report: ResetReport = {
      mode,
      executed: false,
      timestamp: nowIso(),
      databaseHost: summary.host,
      databaseName: summary.database,
      keepTablesConfigured: KEEP_TABLES,
      keepTablesExisting: keepCounts,
      deletePlanConfigured: DELETE_PLAN,
      deletePlanResolved: resolved,
      beforeCounts,
      skippedMissingTables: missing,
      notes: [
        'Este script opera SOLO sobre PostgreSQL cloud mediante DATABASE_URL.',
        'No toca base local ni ejecuta migraciones.',
        'Mantiene intactas tablas de autenticacion/permisos listadas en keepTablesConfigured.',
      ],
    };

    const reportsDir = path.join(process.cwd(), 'cloud-commercial-reset-reports');

    if (mode === 'dry-run') {
      const reportPath = writeJsonReport(reportsDir, mode, report);

      console.log('DRY-RUN completado. No se borraron datos.');
      console.log(`Base objetivo: ${summary.host}/${summary.database}`);
      console.log(`Tablas a conservar: ${existingKeepTables.join(', ') || '(ninguna encontrada)'}`);
      console.log(`Tablas a limpiar (ordenadas): ${orderedTables.join(' -> ') || '(ninguna)'}`);
      console.log(`Reporte JSON: ${reportPath}`);
      return;
    }

    const backupDir = path.join(process.cwd(), 'backups', 'cloud-commercial-reset');
    ensureDirectory(backupDir);
    const backupStamp = sanitizeFileStamp(nowIso());
    const backupPath = path.join(backupDir, `cloud-commercial-reset-backup-${backupStamp}.sql`);

    console.log('Generando backup SQL completo con pg_dump...');
    await runPgDump(backupPath, databaseUrl);

    if (!fs.existsSync(backupPath)) {
      throw new Error(`Backup no encontrado en ${backupPath}`);
    }

    const backupStats = fs.statSync(backupPath);
    if (backupStats.size <= 0) {
      throw new Error(`Backup vacio en ${backupPath}`);
    }

    await deleteCommercialTables(prisma, orderedTables);

    const afterCounts = await countTables(prisma, orderedTables);
    const deletedRowsByTable: TableCount[] = beforeCounts.map((before) => {
      const after = afterCounts.find((item) => item.table === before.table)?.count ?? 0;
      return {
        table: before.table,
        count: before.count - after,
      };
    });

    report.executed = true;
    report.afterCounts = afterCounts;
    report.deletedRowsByTable = deletedRowsByTable;
    report.backup = {
      path: backupPath,
      sizeBytes: backupStats.size,
      createdAt: nowIso(),
    };

    const reportPath = writeJsonReport(reportsDir, mode, report);

    console.log('EXECUTE completado con exito.');
    console.log(`Base objetivo: ${summary.host}/${summary.database}`);
    console.log(`Backup SQL: ${backupPath}`);
    console.log(`Tablas limpiadas (orden): ${orderedTables.join(' -> ') || '(ninguna)'}`);
    console.log(`Reporte JSON: ${reportPath}`);
    console.log('Restauracion de backup (si se requiere):');
    console.log(`  psql "$DATABASE_URL" -f "${backupPath}"`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`ERROR: ${message}`);
  process.exit(1);
});
