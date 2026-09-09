# Sistema Solares Agent Instructions

This file is mandatory for every future Codex session in this repository.

## Before Any Change

1. Read `AGENTS.md`.
2. Read `docs/PRODUCT_SPEC.md`.
3. Read `docs/ARCHITECTURE.md`.
4. Read `docs/DATA_MODEL.md`.
5. Read `docs/BUSINESS_RULES.md`.
6. Read `docs/PROJECT_STATUS.md`.
7. Read `docs/CLOUD_ARCHITECTURE.md`.
8. Read `docs/OFFLINE_ARCHITECTURE.md`.
9. Read `docs/DATA_MIGRATION.md`.
10. Read `docs/API_CONTRACTS.md`.
11. Read `docs/TESTING.md`.
12. Read `docs/BACKUP_ROLLBACK.md`.
13. Read `docs/WINDOWS_STORAGE.md`.
14. Read `docs/OPERATIONS_RUNBOOK.md`.
15. Read `docs/DECISIONS.md`.
16. Read `docs/ENVIRONMENTS.md`.
17. Read any other phase-specific docs only after the baseline above.
18. Run `git status`.

Legacy docs under `docs/sync`, `docs/audit`, or other historical folders preserve useful history, but they MUST NOT override the current baseline documentation. When conflict exists, CURRENT BASELINE DOCS + SOURCE EVIDENCE WIN.

## Non-Negotiable Rules

- Sistema Solares is a SINGLE-COMPANY system.
- Do not invent multi-tenancy.
- Existing `Company`, `companyId`, and `tenantKey` are a FIXED SINGLE-COMPANY NAMESPACE - LEGACY CURRENT IMPLEMENTATION.
- Do not remove `Company`, `companyId`, or `tenantKey` unless a later approved phase explicitly does it.
- Never treat DEV SQLite as customer production.
- Customer production DB lives on the customer's PC.
- Migration work must use a verified COPY of the customer DB, not the live file.
- Before acquiring production data, the customer app must be fully closed, no Sistema Solares process may be running, and the app must not be launched again until acquisition is complete.
- Copy `sistema_solares.db` and, when present in the same acquisition window, `sistema_solares.db-wal`, `sistema_solares.db-shm`, and `sistema_solares.db-journal`.
- Inspect and hash only the copied production artifacts; preserve original customer files untouched.
- PostgreSQL target = source of truth.
- Local DB target = cache, outbox, and device state only.
- No financial data loss.
- No duplicate payment.
- No duplicate active sale for the same lot.
- Offline operation must be idempotent.
- Outbox must survive restart, update, and network/backend failure.
- Audit before modifying.
- Work by phases.
- Every phase ends with tests, risks, and GO/NO-GO.
- Never silently rewrite historical production data.
- Never claim TARGET behavior is already implemented.

## Current Reality

Current operational source is `app_local` + SQLite (`sistema_solares.db`).

The backend is Express + TypeScript + Prisma + PostgreSQL. Current cloud data is not authoritative enough for production.

## Target Direction

PostgreSQL cloud becomes the authoritative business database.

TARGET ARCHITECTURE REQUIREMENT - NOT IMPLEMENTED YET: backend owns validation, financial rules, transactions, idempotency, concurrency protection, and permissions.

Current backend does not yet fully satisfy those guarantees.

Windows local storage becomes cache, durable offline outbox, device state, config, logs, and support/recovery files.
