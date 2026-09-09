# Operations Runbook

Status: future operational guidance. Commands are marked TBD unless validated.

## Client Offline

Expected behavior: continue read operations from cache where available and write durable operations to outbox.

Operator action: verify network status, confirm outbox pending count, do not delete local outbox.

Command: TBD.

## Outbox Pending

Expected behavior: pending operations remain durable across app restart, Windows restart, network failure, backend outage, and app upgrade.

Operator action: inspect pending operation count and last error. Retry only through approved app/service flow.

Command: inspect `%LOCALAPPDATA%\SistemaSolares\data\outbox\outbox.db` only on a copied support bundle unless an approved support procedure allows direct read-only inspection.

## Backend Down

Expected behavior: cloud writes fail safely, outbox remains durable, app reports sync failure.

Operator action: check backend health, deployment status, logs, and recent configuration changes.

Command: TBD.

## PostgreSQL Down

Expected behavior: backend reports database failure; app does not lose pending local operations.

Operator action: check database provider status, connectivity, restore/failover state, and backend logs.

Command: TBD.

## Failed Sync

Expected behavior: failed operations remain in outbox with stable operation identity and retry metadata.

Operator action: classify failure as validation, conflict, network, backend, or database failure.

Command: TBD.

## Legacy Financial Sync Frozen

Expected behavior: when `AUTHORITATIVE_MODE=true`, legacy `/sync/upload` rejects `sales`, `installments`/`cuotas`, and `payments` with `LEGACY_FINANCIAL_SYNC_FROZEN`.

Operator action: confirm the client is using authoritative write endpoints for financial operations. Do not disable the freeze unless an approved transition procedure explicitly requires it.

Command: check backend logs for `[LegacySync]` entries and verify `AUTHORITATIVE_MODE`.

## Migration Failure

Expected behavior: production remains on previous state until cutover. Customer original SQLite remains unchanged.

Operator action: stop migration, preserve logs, keep safe copy, do not mutate original evidence.

Command:

```powershell
cd backend
npx tsx src/scripts/customerSqliteMigration.ts `
  --source "<verified-copy>\sistema_solares.db" `
  --target "<postgres-url>" `
  --output-dir "<evidence-output-dir>" `
  --precheck `
  --migrate `
  --reconcile `
  --allow-working-copy-repair
```

Operator rules:

- never point the command at the live customer DB
- keep `.db`, `.db-wal`, `.db-shm`, and `.db-journal` from the same acquisition window together
- review `customer_migration_report.json` and `customer_migration_report.md`
- stop on `BLOCKING`
- stop if source SHA256 before/after does not match
- stop if reconciliation or financial reconciliation fails
- do not use local cache or app startup sync as a migration substitute

## Reconciliation Mismatch

Expected behavior: cutover is blocked.

Operator action: compare counts, sums, balances, orphan relationships, sync IDs, deleted records, active sales per lot, and installment numbers per sale.

Command: rerun the hardened migration command against a fresh isolated PostgreSQL target and compare generated reports. Any mismatch above the documented currency tolerance blocks cutover unless documented and approved.

Financial reconciliation must compare PostgreSQL `Decimal(14,2)` totals against per-row normalized SQLite values, not raw SQLite floating-point sums.

## Prisma Migration Deploy Failure

Expected behavior: `npx prisma migrate deploy` applies the checked-in migration chain.

Operator action:

- verify `DATABASE_URL` without printing credentials
- verify command working directory is `backend` or the backend container `/app`
- verify Prisma and `@prisma/client` versions match the app package
- verify the target is an isolated migration/UAT/approved production database
- retry from the backend runtime environment if a Windows SSH tunnel gives a schema-engine failure

Fallback command: use the hardened tool with `--allow-sql-fallback` only after Prisma CLI failure is captured. The fallback applies only checked-in immutable `migration.sql` files in order, records `_prisma_migrations` checksums, and fails closed on mismatch.

## Upgrade Failure

Expected behavior: business data remains protected; outbox remains preserved.

Operator action: collect installer/app logs, verify mutable data root, confirm database files still exist, roll back application version if approved.

Command: TBD.

## Rollback

Expected behavior: rollback uses preserved evidence and approved procedure. After cloud cutover, PostgreSQL backup is the business rollback source; local cache is not.

Operator action: identify rollback point, preserve current evidence, restore only through validated procedure.

Command: TBD.

## UAT Backend Rollback

Expected behavior: UAT rollback uses the isolated `altomamita-uat` backup directory and previous immutable UAT image tags only.

Operator action: preserve current evidence, select the intended UAT dump/image, and avoid touching production or other EasyPanel projects.

Command: TBD until a restore drill is separately approved.

## 2026-09-08 Altomamita Production EasyPanel Infrastructure

Status: PRODUCTION INFRASTRUCTURE NORMALIZED / CUSTOMER BUSINESS ROWS UNCHANGED.

Production server: `31.97.99.70`.

EasyPanel project: `altomamita`.

Services:

- backend: `altomamita_altomamita-backend`
- PostgreSQL: `altomamita_altomamita-db`
- PgWeb: `altomamita_altomamita-db_pgweb`

Backend service:

- EasyPanel type: `app`
- source type: `upload`
- build: Dockerfile, file `Dockerfile`
- image: `altomamita_altomamita-backend:prod-finalization-20260908T201059Z`
- internal port: `3000`
- public URL: `https://altomamita-backend.gcdndd.easypanel.host`
- EasyPanel domain id: `codex-altomamita-backend-prod-20260908`
- healthcheck: `http://127.0.0.1:3000/health`
- replicas: `1`
- restart condition: `on-failure`
- CPU limit/reservation: `0.5` / `0.05`
- memory limit/reservation: `512 MiB` / `64 MiB`

PostgreSQL service:

- image: `postgres:17`
- database: `altomamita`
- user: `altomamita_user`
- persistent data path: `/etc/easypanel/projects/altomamita/altomamita-db/data`
- no Swarm-published PostgreSQL port was configured
- host port `25432` belongs to unrelated infrastructure and must not be touched for Sistema Solares
- CPU limit/reservation: `0.5` / `0.05`
- memory limit/reservation: `768 MiB` / `128 MiB`

PgWeb:

- image: `sosedoff/pgweb:0.16.2`
- corrected connection target: database `altomamita`
- root cause fixed: PgWeb previously connected without an explicit database name, so PostgreSQL defaulted to database `altomamita_user` and logged recurring `database "altomamita_user" does not exist`

Operational verification after normalization:

- EasyPanel app overview opens for `altomamita-backend`; it no longer redirects to `/init/build`
- public `/api/health`, `/health`, and `/api/system/status` returned HTTP 200
- auth login, refresh, `/auth/me`, and RBAC users check returned HTTP 200 with `OWNER`
- `altomamita` services were `1/1`
- production business table counts matched: `Client=90`, `Seller=26`, `Lot=135`, `Sale=135`, `Installment=15864`, `Payment=889`
- no recurring PgWeb-origin PostgreSQL `database "altomamita_user" does not exist` error appeared in the checked log window

Safe redeploy procedure:

1. Confirm the service selected in EasyPanel is project `altomamita`, service `altomamita-backend`.
2. Confirm the current image tag and backup state before deploying.
3. Use EasyPanel `Implementar` only for the backend service, or use a targeted Docker service update for `altomamita_altomamita-backend`.
4. Do not touch `daleventapos`, `fullpos`, `ventas`, `appyra`, or host port `25432`.
5. After redeploy, verify public health endpoints, auth flow, service replicas, and production business counts.
