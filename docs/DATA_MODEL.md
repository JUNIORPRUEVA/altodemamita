# Sistema Solares Data Model

Status: current source evidence plus target gap classification. This document does not deploy schema changes or approve production migration.

Phase 1A update: the local Prisma source now contains additive cloud-authoritative data model foundations. These schema changes are local source changes only until an approved migration is applied to a disposable/test database and later to production through the approved process.

## Current Local Database

Current operational DB:

```text
sistema_solares.db
```

Technology:

```text
SQLite via sqflite_common_ffi
```

Current schema version observed in source:

```text
28
```

Current production customer DB lives on the customer's PC. A repository or DEV SQLite file must never be treated as customer production evidence.

## Persistent SQLite Tables

Current persistent application tables through schema version 28:

- `clientes`
- `usuarios`
- `solares`
- `vendedores`
- `ventas`
- `cuotas`
- `pagos`
- `configuracion`
- `informacion_empresa`
- `permisos`
- `configuracion_impresoras`
- `parametros_financieros`
- `informacion_backups`
- `preferencias_backup`
- `sesiones_auth`
- `roles`
- `user_roles`
- `role_permissions`
- `company_profiles`
- `sync_queue`
- `conflict_logs`

SQLite may also contain internal tables such as `sqlite_sequence` or transient migration artifacts during upgrade/rebuild operations. Those internal/migration-only objects are not business entities and must not be treated as missing domain tables.

## Current PostgreSQL Models

Every current Prisma model:

- `User`
- `Company`
- `Client`
- `Seller`
- `Lot`
- `Sale`
- `Installment`
- `Payment`
- `SyncBatch`
- `PaymentReminderNotification`
- `PaymentReminderDelivery`
- `LateFeeSnapshot`
- `AuthoritativeOperation`

`Company`, `companyId`, and `tenantKey` are CURRENT fixed-single-company namespace infrastructure, not a mandate to design multi-tenancy.

## Coverage Definitions

- FULL: current cloud model can represent the local entity sufficiently for current sync/read use.
- PARTIAL: current cloud model represents some core fields but lacks important authority, relationships, or state.
- INSUFFICIENT: current cloud model cannot safely become authoritative for the local business history.
- NONE: no current cloud model exists for the entity as an authoritative business concept.
- MODEL FOUNDATION: Prisma source can represent the entity, but server APIs/business logic/migration validation are not yet complete.

## Master Local To Cloud Matrix

| Local entity | Cloud model | Coverage | Target authority |
|---|---|---|---|
| `clientes` | `Client` | FULL | Cloud business entity after cutover |
| `vendedores` | `Seller` | FULL | Cloud business entity after cutover |
| `solares` | `Lot` | PARTIAL | Cloud business entity after cutover |
| `ventas` | `Sale` | MODEL FOUNDATION | Cloud business entity after service/migration completion |
| `cuotas` | `Installment` | MODEL FOUNDATION | Cloud business entity after service/migration completion |
| `pagos` | `Payment` | MODEL FOUNDATION | Cloud business entity after service/migration completion |
| `usuarios` | `User` | MODEL FOUNDATION | Cloud business auth entity after API/enforcement completion |
| `roles` / `permisos` / `user_roles` / `role_permissions` | `BusinessRole` / `Permission` / link models | MODEL FOUNDATION | Required cloud authorization model |
| `informacion_empresa` / `company_profiles` | `CompanyProfile` plus `Company` namespace | MODEL FOUNDATION | Cloud business profile target |
| `parametros_financieros` | `FinancialParameters` | MODEL FOUNDATION | Required cloud business configuration |
| `configuracion` business keys | `BusinessConfiguration` | MODEL FOUNDATION | Required cloud business configuration |
| `configuracion_impresoras` | None | NONE | Device-local target |
| `sesiones_auth` | None | NONE | Device-local/session cache target |
| `preferencias_backup` / `informacion_backups` | None | NONE | Device-local operational state |
| `sync_queue` | `SyncBatch` only records received/applied counts | PARTIAL | Local durable outbox target, not business history |
| `conflict_logs` | None | NONE | Device-local sync diagnostics/conflict state |

## Entity Mapping

| Local table | Cloud model | Mapping |
|---|---|---|
| `clientes` | `Client` | `clientes.sync_id` -> `Client.syncId` |
| `solares` | `Lot` | `solares.sync_id` -> `Lot.syncId` |
| `vendedores` | `Seller` | `vendedores.sync_id` -> `Seller.syncId` |
| `ventas` | `Sale` | `ventas.sync_id` -> `Sale.syncId` |
| `cuotas` | `Installment` | `cuotas.sync_id` -> `Installment.syncId` |
| `pagos` | `Payment` | `pagos.sync_id` -> `Payment.syncId` |

## Sale Cloud Gap

CURRENT: local `ventas` stores enough information to drive current business behavior, including client, lot, user/operator, optional seller, sale date, sale price, initial percentage, required initial amount, paid initial amount, pending initial amount, reserve/apartado minimum and paid amounts, initial deadline, activation date, financed balance, pending balance, monthly interest, installment count, lifecycle status, soft delete, and sync metadata.

PHASE 1A MODEL FOUNDATION: Prisma `Sale` now includes normalized columns for the local sale contract fields and nullable relations to client, lot, seller, and operator user while preserving sync IDs and raw JSON compatibility.

REMAINING CURRENT CLOUD GAP: server-authoritative sale APIs, validation, financial transitions, concurrency control, production migration validation, and cutover are not implemented.

- user/operator relationship
- required initial amount
- pending initial amount
- initial percentage where applicable
- reservation/apartado values
- initial deadline
- activation date
- financed balance distinct from remaining balance
- interest rate
- installment count
- complete lifecycle semantics
- strong client/lot/seller/user relations

The `raw` JSON field is not sufficient for cloud authority. Current download/record mapping does not round-trip every local field back into the local model, and raw-only authority would leave business rules, constraints, and reconciliation ambiguous.

## Payment Cloud Gap

CURRENT: local `pagos` records sale, client, optional user/operator, optional installment, payment date, amount, method, type, reference, year-to-pay, soft delete, and sync metadata. Current local behavior also mutates installments and sale balances when payments are created or annulled.

PHASE 1A MODEL FOUNDATION: Prisma `Payment` now includes nullable relations to sale, client, installment, receiving user, annulment user, and reversal/original payment; it also adds principal/interest applied and annulment metadata fields while preserving sync IDs and raw JSON compatibility.

REMAINING CURRENT CLOUD GAP: authoritative payment service logic, allocation calculations, duplicate-payment idempotency, cancellation workflow, and production reconciliation are not implemented.

PHASE 1F UAT FOUNDATION: server-side authoritative payment flows now have UAT-verified coverage for installment payment, interest-first allocation, idempotent retry, capital prepayment recalculation, capital-payment blockers, and latest active payment annulment. Production migration/reconciliation and final client cutover remain incomplete.

- receiving user/operator
- payment allocation audit
- cancellation/annulment metadata
- relationship to original/reversed payment where needed
- principal/interest allocation history at payment-event level
- stronger sale/client/installment/user relational integrity

## Other Cloud Gaps

- Installment = MODEL FOUNDATION. Core monetary fields and a nullable sale relation exist, but authoritative service behavior and production validation are incomplete.
- User = MODEL FOUNDATION. Backend `User` has been extended for local user metadata, but user APIs and enforcement are incomplete.
- RBAC = MODEL FOUNDATION. Cloud models exist for roles, role assignments, permissions, and role permissions, but APIs/enforcement are incomplete.
- Financial parameters = MODEL FOUNDATION. `FinancialParameters` exists, but server-side calculation ownership is not wired to it.
- Business configuration = MODEL FOUNDATION. `BusinessConfiguration` exists, but business configuration APIs/server use are incomplete.
- Company profile = MODEL FOUNDATION. `CompanyProfile` exists, but profile APIs/media handling are incomplete.

## Device-Local Versus Cloud-Business Target

DEVICE-LOCAL target:

- `configuracion_impresoras`
- printer selection and device settings
- local sync cursors
- device identity
- local session/cache
- backup preferences and backup history
- technical logs
- durable outbox
- conflict technical state

CLOUD-BUSINESS target:

- company/business profile
- business contact/logo metadata where authoritative
- financial parameters
- business-global configuration
- users, roles, and permissions required for business authorization

Do not claim cloud models already exist for cloud-business target areas where the current Prisma schema has no model.

## Identity Rules

Local IDs are SQLite integers and are operational local foreign keys.

Cloud IDs are UUID primary keys.

Migration and reconciliation identity should use `sync_id`, while preserving enough local ID mapping to rebuild relationships.

Migrations added/backfilled sync metadata. Older records may predate `sync_id`, and the real customer DB copy must still be checked for NULL/missing `sync_id`, duplicate `sync_id`, and malformed historical identifiers before production migration.

## Relationship Rules

Local relationships use SQLite integer IDs:

- `ventas.cliente_id` -> `clientes.id`
- `ventas.solar_id` -> `solares.id`
- `ventas.usuario_id` -> `usuarios.id`
- `ventas.vendedor_id` -> `vendedores.id`
- `cuotas.venta_id` -> `ventas.id`
- `pagos.venta_id` -> `ventas.id`
- `pagos.cliente_id` -> `clientes.id`
- `pagos.cuota_id` -> `cuotas.id`

Cloud business relationships currently rely heavily on sync IDs, such as `clientSyncId`, `lotSyncId`, `saleSyncId`, and `installmentSyncId`, rather than strong Prisma relations between every business entity.

## Money

Local stores financial values as SQLite `REAL`.

Cloud stores monetary values as Prisma Decimal fields, commonly `Decimal(14,2)`.

Current app behavior rounds currency to 2 decimals and uses tolerance around `0.009` for paid/balance checks.

## Soft Delete

Local soft delete uses `deleted_at`.

Cloud soft delete uses `deletedAt`.

Soft-deleted records must be preserved during migration and reconciliation.
