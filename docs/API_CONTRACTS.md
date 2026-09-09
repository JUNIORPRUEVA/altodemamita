# API Contracts

Status: current endpoint documentation plus missing target API markers. Proposed target APIs are marked `NOT IMPLEMENTED / REQUIRED`.

## Current Mount Points

Current route groups are mounted with both `/api/...` and non-`/api` aliases:

- `/api/auth` and `/auth`
- `/api/authoritative` and `/authoritative`
- `/api/owner` and `/owner`
- `/api/payment-reminders` and `/payment-reminders`
- `/api/sync`, `/sync`, `/api/pos-sync`, and `/pos-sync`
- `/api/system` and `/system`

Health endpoints:

- `GET /`
- `GET /health`
- `GET /api/health`

## Current Auth

Current auth uses backend `User` records and JWT bearer tokens. Roles are limited to `OWNER` and `TECH`.

Existing endpoints:

- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`

CURRENT AUTH CONTRACT MISMATCH:

The local app attempts `/auth/refresh`, but the current backend route definitions do not define `POST /auth/refresh`. Do not invent or assume a refresh-token implementation in documentation or code until an approved implementation phase adds it.

Missing target APIs:

- Full user management: FOUNDATION IMPLEMENTED / BROADER CLIENT UX REQUIRED
- Roles management: FOUNDATION IMPLEMENTED
- Permissions management: FOUNDATION IMPLEMENTED
- Password reset policy compatible with local metadata: NOT IMPLEMENTED / REQUIRED

## Current Sync

Current sync accepts and returns the core scopes:

- clients
- sellers
- lots/solares/products
- sales
- installments/cuotas
- payments

Existing endpoints:

- `POST /sync/upload`
- `GET /sync/download`
- `GET /sync/changes`
- `GET /sync/status`

TRANSITIONAL SECURITY:

`POST /sync/upload` now supports JWT-authenticated legacy sync. Temporary anonymous legacy upload is controlled by `LEGACY_SYNC_ALLOW_ANONYMOUS`; UAT defaults to rejecting anonymous upload. When `AUTHORITATIVE_MODE=true`, financial legacy upload scopes are frozen and rejected with `LEGACY_FINANCIAL_SYNC_FROZEN` for `sales`, `installments`/`cuotas`, and `payments`.

Current sync does not provide complete authoritative contracts for:

- users: NOT IMPLEMENTED / REQUIRED
- roles: NOT IMPLEMENTED / REQUIRED
- permissions: NOT IMPLEMENTED / REQUIRED
- company profile: NOT IMPLEMENTED / REQUIRED
- financial parameters: NOT IMPLEMENTED / REQUIRED
- business configuration: NOT IMPLEMENTED / REQUIRED
- document/media metadata: NOT IMPLEMENTED / REQUIRED

## Current Owner Views

Owner routes expose dashboard/list/detail style data from current cloud records. They do not replace full business write APIs.

Existing endpoints:

- `GET /owner/dashboard`
- `GET /owner/clients`
- `GET /owner/sellers`
- `GET /owner/lots`
- `GET /owner/solares`
- `GET /owner/sales`
- `GET /owner/ventas`
- `GET /owner/installments`
- `GET /owner/cuotas`
- `GET /owner/payments`
- `GET /owner/pagos`
- `GET /owner/sync-status`

## Current System

Existing endpoints:

- `GET /system/status`
- `GET /system/config`

## Current Payment Reminders

Existing endpoints:

- `GET /payment-reminders/sales/:saleSyncId/overdue-summary`
- `POST /payment-reminders/sales/:saleSyncId/send`
- `POST /payment-reminders/run`
- `GET /payment-reminders/whatsapp/webhook`
- `POST /payment-reminders/whatsapp/webhook`

## Current Authoritative Business Writes

Status: IMPLEMENTED LOCALLY - NOT DEPLOYED.
UAT status: IMPLEMENTED AND VERIFIED for Phase 1F foundation scenarios.

All endpoints require JWT bearer authentication and a durable operation identity via `Idempotency-Key`, `idempotencyKey`, or `operationId`.

Implemented endpoints:

- `POST /authoritative/sales`
- `POST /authoritative/payments`
- `POST /authoritative/payments/:paymentId/annul`
- `POST /authoritative/sales/:saleId/cancel`

Cancellation behavior:

- blocks cancellation while active/non-annulled payments exist
- cancels clean sales atomically
- preserves sale/installment/payment history
- never hard-deletes lots
- restores the lot to `disponible` only for clean cancellation

Idempotency behavior:

- same company + same operation key + same payload returns the stored response
- same company + same operation key + different payload returns `409 IDEMPOTENCY_KEY_CONFLICT`
- missing operation key returns `400 IDEMPOTENCY_KEY_REQUIRED`

Current business API foundation:

- `GET /business/users`
- `POST /business/users`
- `GET /business/roles`
- `POST /business/roles`
- `POST /business/users/:userId/roles`
- `POST /business/permissions`
- `POST /business/roles/:roleId/permissions`
- `GET /business/company-profile`
- `PUT /business/company-profile`
- `GET /business/financial-parameters`
- `PUT /business/financial-parameters`
- `GET /business/business-config`
- `PUT /business/business-config/:key`

Phase 2 client foundation maps local cloud helper methods to these auth/business endpoints and to the authoritative sale/payment endpoints above. This is client foundation only; production cutover still requires customer migration, reconciliation, and end-to-end UAT signoff.

Business configuration uses an allow-list and excludes device-local settings such as printers, local paths, sync cursors, local auth cache, backup preferences, and logs.

Error model:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message"
  }
}
```

## Required Target API Concepts

The following are required but not currently documented as implemented contracts:

- idempotent sale creation: IMPLEMENTED LOCALLY / UAT REQUIRED
- idempotent payment creation: IMPLEMENTED LOCALLY / UAT REQUIRED
- payment cancellation/reversal audit: IMPLEMENTED LOCALLY FOR LATEST ACTIVE PAYMENT / UAT REQUIRED
- sale cancellation audit: FOUNDATION IMPLEMENTED / BUSINESS REVIEW STILL REQUIRED
- server-side financial calculation endpoint: NOT IMPLEMENTED / REQUIRED
- authoritative business configuration endpoint: NOT IMPLEMENTED / REQUIRED
- authoritative company profile/media endpoint: NOT IMPLEMENTED / REQUIRED
- migration import/reconciliation endpoint or validated tool contract: NOT IMPLEMENTED / REQUIRED
