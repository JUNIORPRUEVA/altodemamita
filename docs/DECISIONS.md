# Sistema Solares Decisions

## ADR-001 Single Company

Status: Accepted.

Sistema Solares is a SINGLE-COMPANY application. Do not design multi-tenancy.

## ADR-002 PostgreSQL Target Authority

Status: Accepted.

PostgreSQL cloud is the target authoritative business database.

## ADR-003 Local Cache / Outbox / State Only

Status: Accepted.

After cloud cutover, local Windows storage is not authoritative business history. It is cache, durable offline outbox, device state, config, logs, and support/recovery.

## ADR-004 Keep Company/companyId Temporarily

Status: Accepted.

Existing `Company`, `companyId`, and `tenantKey` remain because backend sync, constraints, status, batches, and reminders depend on them.

Document as: FIXED SINGLE-COMPANY NAMESPACE - LEGACY CURRENT IMPLEMENTATION.

## ADR-005 Migration From Customer SQLite COPY

Status: Accepted.

Production migration must use a verified copy of the customer SQLite DB and sidecars. Never operate directly on the live customer DB.

## ADR-006 Financial Reconciliation Required

Status: Accepted.

SQLite `REAL` values and PostgreSQL Decimal values must be reconciled to current app behavior before cloud authority.

## ADR-007 Durable Idempotent Offline Outbox

Status: Accepted.

Offline operations must have stable IDs/idempotency and survive restart, update, network loss, and backend outage.

## ADR-008 Separate Cache And Outbox Stores

Status: Accepted.

Cache and outbox should be separate logical stores, preferably separate physical stores, so cache corruption or cleanup cannot destroy pending operations.

## ADR-009 Predictable Windows Mutable Data Tree

Status: Accepted.

Mutable data should live under a predictable user-writable SistemaSolares tree, not under Program Files.

Recommended mutable root:

```text
%LOCALAPPDATA%\SistemaSolares
```

## ADR-010 No Automatic Production DB Upload At Startup

Status: Accepted.

Do not automatically upload a production customer DB on application startup. Production migration must be controlled, explicit, verified, and reversible.
