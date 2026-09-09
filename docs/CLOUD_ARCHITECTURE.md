# Cloud Architecture

Status: target requirements only. This document does not approve implementation or define final code.

## Current Cloud Shape

The backend currently uses PostgreSQL with Prisma models for users, company tenancy, clients, sellers, lots, sales, installments, payments, sync batches, payment reminders, reminder deliveries, and late-fee snapshots.

The current cloud model can receive core sync records, but it cannot reconstruct all local business state because sales, payments, RBAC, financial parameters, business configuration, and company profile data are incomplete.

Phase 1A local source update: Prisma now contains additive data model foundations for those missing areas. These are schema/source foundations only. They are not a production deployment, not a completed business service layer, and not a completed migration/cutover.

Phase 1F UAT update: backend foundation services and APIs for authoritative sales/payments, auth refresh, RBAC enforcement, business profile/configuration, financial parameters, and legacy sync financial freeze have been implemented and verified in UAT. This remains a backend foundation, not a production cutover.

CURRENT SECURITY GAP - REQUIRED BEFORE CLOUD-AUTHORITATIVE CUTOVER: backend sync routes currently do not appear to be mounted with `authGuard` or `syncGuard`. This document does not approve current sync routes for production-authoritative writes.

CURRENT AUTH CONTRACT MISMATCH: the local app attempts `/auth/refresh`, but the current backend route definitions do not define that endpoint.

## Current Business Configuration Coverage

Current cloud coverage is incomplete:

- Sale/payment behavior authority = FOUNDATION IMPLEMENTED AND UAT VERIFIED
- Installment service/integrity validation = PARTIAL
- User APIs/enforcement = FOUNDATION IMPLEMENTED
- RBAC APIs/enforcement = FOUNDATION IMPLEMENTED
- Financial parameters server use = FOUNDATION IMPLEMENTED
- Business configuration APIs/server use = FOUNDATION IMPLEMENTED
- Company profile APIs/media handling = FOUNDATION IMPLEMENTED FOR METADATA/REMOTE URL

DEVICE-LOCAL current/target state includes printer configuration, printer selection, local sync cursors, device identity, local sessions/cache, backup preferences/history, technical logs, outbox, and conflict technical state.

CLOUD-BUSINESS target state includes company/business profile, authoritative business contact/logo metadata, financial parameters, business-global configuration, and users/roles/permissions needed for business authorization.

## Target Requirement

PostgreSQL must become capable of reconstructing all business state needed to operate after cutover. Local SQLite must no longer be the business source of truth after the cloud-authoritative migration is complete.

Cloud-authoritative entities:

- clients
- sellers
- lots
- sales
- installments
- payments
- users
- roles
- permissions
- business profile
- financial parameters
- business configuration

## Required Server Concepts

Server transactions are required for business operations that touch multiple records, especially sales, installments, payments, lot status, balances, cancellation, and reconciliation metadata.

Idempotency is required for retryable writes. Every operation that can be retried after a timeout must have stable operation identity and must be safe to replay.

Foreign keys are required for authoritative relationships:

- sale to client
- sale to lot
- sale to seller, nullable where business rules allow
- sale to user/operator
- installment to sale
- payment to sale
- payment to client
- payment to installment, nullable for non-installment payments
- payment to user/operator
- user roles and role permissions

Unique constraints are required for:

- one active client per document per company
- one active seller per document per company
- one active lot per block/number per company
- one active sale per lot
- one installment number per sale
- stable sync identifiers per company
- stable operation identifiers for idempotent writes

Payment audit must preserve who received, created, updated, cancelled, or reversed a payment; when it happened; the reason; and how balances were recalculated.

Server financial ownership is required. Sale financing formulas, financial parameters, payment allocation, late fees, balance recalculation, and status transitions must have a single authoritative server definition before cloud cutover.

## Still Not Complete

The backend foundation is not a production cutover. Remaining work includes client integration design, full customer migration/reconciliation from verified SQLite copy, broader acceptance testing, final RBAC UX/policy hardening, and production deployment planning.
