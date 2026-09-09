# Sistema Solares Project Status

## Audit Baseline

Audits complete: YES

Completed audit areas:

- Client/local architecture
- Backend architecture
- Production data acquisition
- Local vs cloud reconciliation
- Cloud data completeness
- Windows storage architecture

## Current State

Current operational source:

```text
app_local + SQLite sistema_solares.db
```

Current cloud backend:

```text
Express + TypeScript + Prisma + PostgreSQL
```

Current cloud data completeness:

```text
NO-GO
```

Current cloud is not authoritative enough for production.

Phase 1A local schema foundation:

```text
IMPLEMENTED LOCALLY - NOT DEPLOYED
```

The Prisma source now contains additive model foundations for complete sale/payment representation, relational links, user/RBAC, company profile, financial parameters, and business configuration. Server-authoritative workflows, production migration, deployment, and cutover are still not complete.

Phase 1D server-authoritative sale/payment foundation:

```text
IMPLEMENTED LOCALLY - NOT DEPLOYED
```

The backend now has authenticated local endpoints and domain services for idempotent sale creation, payment registration, capital payment handling, and latest-payment annulment. Sale cancellation is intentionally deferred because the final business rule for reversals and lot release still requires UAT approval.

Phase 1F backend cloud closure:

```text
IMPLEMENTED AND VERIFIED IN UAT
```

UAT backend `altomamita-backend-uat` now validates the Phase 1D/1F backend foundation against real PostgreSQL `altomamita_uat`. Verified areas include corrected capital-payment recalculation, auth refresh, RBAC denial, authenticated authoritative writes, legacy financial sync freeze, company profile API, financial parameter API/default ownership, business configuration API, safe sale cancellation, idempotency, and transaction rollback.

## Missing Before Cloud Authority

Known missing/incomplete areas:

- Sale behavior/service authority foundation implemented and UAT verified
- Payment behavior/service authority foundation implemented and UAT verified for tested current-rule flows
- Installment relational integrity incomplete
- User/RBAC runtime APIs and authoritative endpoint enforcement implemented and UAT verified at foundation level
- financial parameters API and default server use implemented and UAT verified
- company profile and business configuration APIs implemented and UAT verified
- strong constraints partially implemented in schema foundation, not validated in production
- server-owned financial rules incomplete
- authoritative sync/outbox architecture not implemented
- legacy sync transitional authorization and authoritative-mode financial write freeze implemented and UAT verified
- auth refresh mismatch
- cache/outbox/state local foundation implemented for Phase 2 UAT only

CURRENT SECURITY GAP - REQUIRED BEFORE CLOUD-AUTHORITATIVE CUTOVER: backend sync routes currently do not appear to be mounted with `authGuard` or `syncGuard`.

CURRENT AUTH CONTRACT MISMATCH: the local app attempts `/auth/refresh`, but the current backend does not define that endpoint.

## Windows Storage

Windows storage design:

```text
GO
```

Recommended target keeps install root separate from mutable data root. Mutable data belongs under a predictable user-writable SistemaSolares tree.

## Implementation

Implementation started:

```text
YES - PHASE 1A LOCAL DATA MODEL FOUNDATION ONLY
```

Functional business flow rewrite, production deployment, production migration, and cloud-authoritative cutover have not started.

## Customer Production Migration

Customer production migration:

```text
NOT STARTED
```

Next migration work must start from a verified copy of the customer production SQLite DB and sidecars.

## Current Guardrails

- Single company only.
- Do not invent multi-tenancy.
- Do not treat DEV SQLite as production.
- Do not silently rewrite historical production data.
- Do not claim target behavior exists until implemented and tested.

## Current Status Summary

AUDIT BASELINE:
COMPLETE

DOCUMENTATION BASELINE:
UNDER FINAL CORRECTION / REVIEW

CLOUD-AUTHORITATIVE IMPLEMENTATION:
DATA MODEL FOUNDATION STARTED LOCALLY

CURRENT CLOUD READINESS:
NO-GO

MAIN IMPLEMENTATION BLOCKERS:

- Sale server-authoritative service foundation implemented and UAT verified
- Payment server-authoritative service foundation implemented and UAT verified for current tested flows
- User/RBAC APIs and authoritative enforcement implemented at foundation level
- business/financial configuration APIs and server default ownership implemented at foundation level
- relational constraints not validated against production data
- financial server authority incomplete
- idempotency/concurrency foundation UAT verified
- legacy sync authorization and financial-scope freeze implemented for transition
- auth refresh mismatch
- cache/outbox/state local foundation implemented for Phase 2 UAT only

PRODUCTION MIGRATION:
NOT STARTED

REAL CUSTOMER DB:
NOT AVAILABLE ON DEV PC

## Phase 2 Foundation Update

Status: LOCAL FOUNDATION IMPLEMENTED / NOT A CUTOVER.

Implemented locally in `app_local`:

- Windows mutable storage now includes `data/cache/cache.db`, `data/outbox/outbox.db`, and `data/state/device_state.db`.
- Cloud foundation databases are physically separated for rebuildable cache, durable outbox, and device state.
- `CLOUD_CUTOVER_MODE` defaults to `LEGACY_LOCAL`; cloud-authoritative client writes require `CLOUD_UAT` or `CLOUD_AUTHORITATIVE`.
- Legacy SQLite financial sync scopes are blocked in cloud cutover modes to prevent dual writes.
- Local cloud client helpers cover auth, authoritative sale/payment operations, company profile, financial parameters, and business configuration.
- SQLite migration tool can inspect a safe SQLite copy, generate reports, and create synthetic test data.

Not done:

- No customer production data was used.
- No customer production database was modified.
- No production backend or production PostgreSQL cutover was performed.

## 2026-09-08 Finalization Sprint Update

Status: BACKEND DEPLOYED / CUSTOMER DATA CUTOVER COMPLETED TO POSTGRESQL / DESKTOP INSTALLER RELEASE STILL REQUIRES FINAL APPROVAL.

Production backend service `altomamita_altomamita-backend` was updated on server `31.97.99.70` to image `altomamita_altomamita-backend:prod-finalization-20260908T201059Z`.

Pre-deploy backup was created and restore-listed:

```text
/etc/easypanel/projects/altomamita/backups/pre-deployment/altomamita_predeploy_20260908T201049Z.dump
SHA256=d304870c66d4de7281596a3e1be0285ab5efda19eaf4d6b80714d6f0354b6bf8
```

After later approved production cutover work on 2026-09-08, production PostgreSQL business table counts were verified as:

```text
Client=90
Seller=26
Lot=135
Sale=135
Installment=15864
Payment=889
```

Production public backend URL is verified:

```text
https://altomamita-backend.gcdndd.easypanel.host
```

Old `onqyr1.easypanel.host` URLs and the direct server IP `/api/health` returned `404`; do not build a customer installer with those values.

## 2026-09-08 EasyPanel Production Infrastructure Normalization

Status: COMPLETE.

Production EasyPanel project `altomamita` was normalized so `altomamita-backend` is a manageable EasyPanel app service with:

- `source.type=upload`
- Dockerfile build using `Dockerfile`
- primary domain `altomamita-backend.gcdndd.easypanel.host`
- EasyPanel domain id `codex-altomamita-backend-prod-20260908`
- image `altomamita_altomamita-backend:prod-finalization-20260908T201059Z`

The EasyPanel UI was visually verified to open the normal app overview instead of redirecting to `/init/build`.

PgWeb was corrected to connect explicitly to database `altomamita`; this stopped the recurring PostgreSQL error for missing database `altomamita_user`.

No customer financial/business rows were modified during this infrastructure normalization.
