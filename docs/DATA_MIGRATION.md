# Data Migration

Status: documentation only. No migration code is approved by this document.

## Production Acquisition Safety

Customer production DB is NOT on this development PC. Development DB files are not production evidence.

Before acquiring production data:

1. The customer application MUST be fully closed.
2. Confirm no Sistema Solares process is running.
3. DO NOT launch the application before acquisition completes.
4. Copy `sistema_solares.db`.
5. Also copy sidecars from the same acquisition window when present:
   - `sistema_solares.db-wal`
   - `sistema_solares.db-shm`
   - `sistema_solares.db-journal`
6. Keep DB and sidecars together as one evidence set.
7. Preserve original customer files untouched.
8. Inspect ONLY the copy.
9. Determine `PRAGMA user_version` only on the copy.
10. Hash copied artifacts where appropriate.

Production migration works from COPY, never the original customer files.

## Canonical Migration Flow

```text
CUSTOMER SQLITE ORIGINAL
        |
        v
SAFE COPY
        |
        v
INSPECT COPY
        |
        v
MIGRATE COPY
        |
        v
POSTGRESQL
        |
        v
RECONCILE
        |
        v
VALIDATE
        |
        v
CUTOVER
```

LAB/STAGING may be inserted as an additional controlled environment for rehearsal and validation. That does not change the fundamental production rule: production migration operates from a safe SQLite copy, not from the live original and not from automatic application startup upload.

## Required Evidence Preservation

The customer original SQLite database must remain immutable rollback evidence. Migration work must use safe copies only.

## Validation

Validation must identify schema version, database integrity, required tables, orphan records, deleted records, duplicate business keys, invalid dates, invalid numeric values, and sync identifier quality.

Before production migration, the customer DB copy MUST be checked for:

- NULL / missing `sync_id`
- duplicate `sync_id`
- malformed historical `sync_id` if relevant
- broken local relationships
- orphan records
- duplicate active lot sales

Do not state or assume that `sync_id` is automatically trustworthy merely because schema migration v14 created/backfilled it.

## Hardened Migration Tool

Phase hardening added a formal backend CLI. It is not called by app startup.

Required explicit invocation shape:

```powershell
cd backend
npx tsx src/scripts/customerSqliteMigration.ts `
  --source "<verified-sqlite-copy>\sistema_solares.db" `
  --target "<postgres-url>" `
  --output-dir "<evidence-output-dir>" `
  --precheck `
  --migrate `
  --reconcile `
  --allow-working-copy-repair
```

The tool refuses to run unless `--precheck`, `--migrate`, and/or `--reconcile` is explicitly supplied. PostgreSQL work requires `--target`.

Source safety behavior:

- calculates SHA256 for the source copy before work
- creates a separate working copy
- detects and reports `.db`, `.db-wal`, `.db-shm`, and `.db-journal`
- copies sidecars with the working copy when present
- runs SQLite inspection read-only where practical
- applies repair actions only to the working copy
- verifies the source SHA256 after work
- writes `customer_migration_report.json` and `customer_migration_report.md`

Precheck statuses:

- `PASS`: safe to proceed
- `REPAIRABLE_ON_WORKING_COPY`: repair may be applied only to the working copy, for example index rebuild via `REINDEX`
- `BLOCKING`: do not write to PostgreSQL until the issue is understood and corrected through an approved path

Mandatory precheck coverage:

- `PRAGMA integrity_check`
- `PRAGMA quick_check`
- `PRAGMA user_version`
- expected business tables
- missing, duplicate, and malformed `sync_id`
- orphan sales, installments, and payments
- duplicate active sale per lot
- duplicate installment number per sale
- invalid/null financial fields
- invalid status values
- FK-like relationship validation
- `configuracion` key classification

## SQLite REAL Money Policy

All SQLite `REAL` monetary values are normalized per row to two decimal places before PostgreSQL insertion and financial reconciliation.

Do not compare raw SQLite floating-point `SUM(...)` values directly against PostgreSQL `Decimal(14,2)` totals. Reconciliation must compare PostgreSQL totals against the sum of per-row normalized values.

The centralized implementation is `normalizeMoney` in `backend/src/services/sqliteCustomerMigration.service.ts`.

Covered monetary areas include sale totals, sale balances, payments, principal, interest, paid principal, paid interest, installment amounts, and remaining installment principal.

## Business Configuration Migration Policy

`configuracion` keys are fail-closed and classified as:

- `CLOUD_BUSINESS`
- `DEVICE_LOCAL`
- `AUTH_SESSION`
- `SYNC_RUNTIME`
- `BACKUP_LOCAL`
- `PRINTER_LOCAL`
- `UNKNOWN`

Only `CLOUD_BUSINESS` keys migrate into `BusinessConfiguration`.

Currently allowed cloud-business keys:

- `business_name`
- `currency_symbol`
- `default_payment_method`
- `sale_default_down_payment_percentage`
- `sale_default_installment_count`
- `sale_default_monthly_interest`

`UNKNOWN` keys are reported and are not migrated automatically.

## Prisma Migration Deployment

Preferred schema deployment is:

```powershell
npx prisma migrate deploy
```

The prior blank schema-engine failure was reproduced only from the Windows SSH tunnel path. In UAT, `prisma migrate deploy` succeeded from inside the backend container against isolated database `altomamita_dev_migration_uat`.

If Prisma CLI cannot run in a controlled customer migration environment, the tool has an automated fallback guarded by `--allow-sql-fallback`. The fallback applies only checked-in `migration.sql` files in sorted migration directory order, records checksums in `_prisma_migrations`, verifies existing migration history, and fails closed on checksum mismatch or SQL failure. Manual ad-hoc `psql` commands are not the approved customer procedure.

## Transform

Transform must map local SQLite records into the approved PostgreSQL model only after all required cloud model gaps are closed. Automatic production DB upload during application startup is prohibited.

Migration identity is deterministic from stable source identity (`sync_id` or approved stable fallback) so repeat runs and same-target replays do not create duplicate business rows.

## Reconciliation Scope

Exact reconciliation is required for:

- clients
- lots
- sales
- installments
- payments

## Reconciliation Checks

Required checks:

- counts by entity
- counts by active/deleted state
- sum of sale totals
- sum of sale balances
- sum of installment principal
- sum of installment interest
- sum of installment paid amounts
- sum of payment amounts
- balance consistency by sale
- orphan client relationships
- orphan lot relationships
- orphan sale relationships
- orphan installment relationships
- sync ID uniqueness
- missing sync IDs
- deleted record preservation
- one active sale per lot
- one installment number per sale

Hardened reconciliation also checks:

- statuses
- soft-deleted counts
- PostgreSQL relationship backfill
- duplicate PostgreSQL sync identities
- principal paid
- interest paid where derivable
- per-row normalized financial totals within current currency tolerance

## Cutover

Cutover cannot proceed if reconciliation differs without a documented, approved explanation. Production PostgreSQL becomes authoritative only after application testing and business signoff.

## Phase 2 Synthetic Migration Tool

Local foundation implemented in `app_local`:

- `SqliteMigrationTool.inspect(<sqlite-copy-path>)` opens a SQLite copy read-only.
- `SqliteMigrationTool.createSyntheticDatabase(<path>)` creates synthetic UAT data only.
- CLI: `dart run tool/phase2_sqlite_migration_tool.dart <sqlite-copy-path> [output-dir]`.
- CLI synthetic mode: `dart run tool/phase2_sqlite_migration_tool.dart --create-synthetic <sqlite-path> [output-dir]`.

The tool reports schema/table availability, counts, active/deleted counts, sync ID quality, relationship orphans, duplicate active sale per lot, and money totals. It does not read or modify the live customer production database.

This Phase 2 Dart inspection tool remains useful for local inspection, but the hardened customer-copy migration command lives in the backend and is the current migration pipeline foundation.
