# Testing Requirements

Status: future implementation test plan. This document does not claim these tests already exist.

Phase 1D local backend evidence:

- `npx prisma validate`: passed
- `npm run build`: passed
- `npm test`: passed, 32 tests

Phase 1F local backend evidence:

- `npx prisma validate`: passed
- `npx prisma generate`: passed
- `npm run build`: passed
- `npm test`: passed, 34 tests

Phase 1F UAT PostgreSQL evidence:

- financed sale: passed
- duplicate sale prevention: passed
- same operation replay: passed
- normal payment: passed
- payment duplicate prevention: passed
- corrected capital payment: passed
- capital-payment blockers: passed
- payment annulment: passed
- safe sale cancellation: passed
- auth refresh: passed
- RBAC denial: passed
- anonymous authoritative write denial: passed
- legacy financial sync write freeze: passed
- company profile read/write: passed
- financial parameters read/write/default use: passed
- business configuration allow-list: passed

Phase 2 local Flutter evidence:

- `flutter test test/phase2`: passed, 7 tests
- `flutter analyze`: passed, no issues

Phase 2 covered locally:

- Windows cache/outbox/state storage layout
- physical separation of `cache.db`, `outbox.db`, and `device_state.db`
- cache rebuild preserving outbox/device state files
- outbox idempotent enqueue and durable retry state
- outbox success, conflict replay, and retryable failure processing
- `CLOUD_UAT` offline sale/payment enqueue
- legacy local mode blocks cloud operation service
- synthetic SQLite migration inspection and reconciliation

## Migration Pipeline Hardening Evidence

Development SQLite copy:

```text
tmp\cliente_sistema_solares.db
```

This was treated as development data only, not customer production.

Precheck evidence:

- source SHA256 before/after matched
- sidecars were detected and reported
- working copy was created
- index inconsistency was repaired only on the working copy using `REINDEX`
- post-repair `PRAGMA integrity_check`: `ok`
- post-repair `PRAGMA quick_check`: `ok`
- `user_version`: 28
- missing sync IDs: 0
- duplicate sync IDs: 0
- relationship orphans: 0
- duplicate active sale per lot: 0
- duplicate installment number per sale: 0
- invalid financial fields: 0
- unknown business config keys: 0

Backend automated tests:

- `npm run build`: passed
- `npm test`: passed, 38 tests

New hardening test coverage:

- SQLite `REAL` money is normalized per row before totals
- floating-point artifacts such as `0.1 + 0.2` and `100.10000000000001`
- large sums of many rows
- business configuration key classification and fail-closed unknowns
- deterministic migration UUIDs
- failure injection for duplicate sync ID, orphan payment, duplicate active sale, invalid financial amount, and unknown config key

UAT PostgreSQL evidence:

- isolated database: `altomamita_dev_migration_uat`
- production database touched: NO
- customer data used: NO
- `prisma migrate deploy`: passed inside UAT backend container
- migration import: passed
- reconciliation: passed
- financial reconciliation: passed
- same-target replay: passed, no duplicate rows
- clean target second run: passed with same counts and financial totals

Realistic development counts migrated:

- clientes: 77
- vendedores: 24
- solares: 98
- ventas: 93
- cuotas: 10932
- pagos: 103
- usuarios: 6
- roles: 5
- permissions: 52
- user_roles: 6
- role_permissions: 0
- company_profile: 1
- financial_parameters: 1
- business_configuration: 6

Financial reconciliation used per-row normalized SQLite totals:

- sale totals: 54939104.00
- payment totals: 6275037.82
- sale balances: 48696922.07
- principal paid: 14489.35
- interest paid: 32856.06
- remaining installment principal: 41754892.81

Raw SQLite floating-point remaining principal was 41754902.95 and is not the authoritative comparison value.

New Phase 1D unit coverage:

- financing formula parity with local sale calculator
- month-end due date behavior
- sale status resolution for apartado/inicial/activa
- installment payment interest-first application
- overdue installment selection

Future cloud-authoritative implementation must test:

- double payment retry
- timeout after server commit
- same lot sold twice concurrently
- offline payment
- offline sale
- app restart with pending outbox
- Windows restart
- backend unavailable
- PostgreSQL unavailable
- cache corruption
- cache deletion
- outbox preservation
- app upgrade
- migration repeatability
- REAL to DECIMAL conversion
- cancelled payment
- cancelled sale
- capital payment
- large DB migration

## Required Test Evidence

Each test must define setup, operation identity, expected server state, expected local state, retry behavior, and reconciliation assertions.

## Minimum Acceptance Areas

Business acceptance must cover sales, installments, payments, lots, clients, sellers, users, roles, permissions, financial parameters, and business configuration.

Operational acceptance must cover outage recovery, restart recovery, failed sync handling, and rollback evidence.

## 2026-09-08 Finalization Sprint Evidence

Local gates run during finalization:

- `backend`: `npm test` passed, 40 tests.
- `backend`: `npm run build` passed.
- `app_local`: `flutter analyze` passed after URL hardening.
- `app_local`: `flutter test --concurrency=1 --dart-define=ALLOW_CLOUD_PULL=true` passed after URL hardening, 391 tests.

Important test runtime note: download/conflict tests that exercise cloud pull require `--dart-define=ALLOW_CLOUD_PULL=true`. The production app still defaults cloud pull to disabled unless explicitly enabled at build time.
