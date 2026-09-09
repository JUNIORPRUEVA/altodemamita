import {
  MigrationCliOptions,
  runCustomerSqliteMigration,
} from '../services/sqliteCustomerMigration.service';

function parseArgs(argv: string[]): MigrationCliOptions {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected positional argument: ${arg}`);
    }
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      flags.add(key);
    } else {
      values.set(key, next);
      i++;
    }
  }

  const source = values.get('source');
  const outputDir = values.get('output-dir');
  if (!source || !outputDir) {
    throw new Error(
      'Required usage: tsx src/scripts/customerSqliteMigration.ts --source <sqlite COPY> --output-dir <dir> [--target <postgres-url>] --precheck [--migrate] [--reconcile]',
    );
  }
  if (!flags.has('precheck') && !flags.has('migrate') && !flags.has('reconcile')) {
    throw new Error('Refusing to run: explicitly pass --precheck, --migrate, and/or --reconcile.');
  }
  if ((flags.has('migrate') || flags.has('reconcile') || flags.has('deploy-schema')) && !values.get('target')) {
    throw new Error('A PostgreSQL --target is required for --deploy-schema, --migrate, or --reconcile.');
  }

  return {
    source,
    target: values.get('target'),
    outputDir,
    precheck: flags.has('precheck'),
    migrate: flags.has('migrate'),
    reconcile: flags.has('reconcile'),
    deploySchema: flags.has('deploy-schema'),
    allowSqlFallback: flags.has('allow-sql-fallback'),
    allowWorkingCopyRepair: flags.has('allow-working-copy-repair'),
    repeatability: flags.has('repeatability'),
    replay: flags.has('replay'),
    companyTenantKey:
      values.get('company-tenant-key') ??
      'sistema-solares-single-company-customer-migration',
    companyName: values.get('company-name') ?? 'Sistema Solares Customer Migration',
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const report = await runCustomerSqliteMigration(options);
  console.log(`Migration report: ${options.outputDir}`);
  console.log(`Final status: ${report.finalStatus}`);
  if (report.p0.length > 0) {
    for (const issue of report.p0) {
      console.error(`P0: ${issue}`);
    }
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
