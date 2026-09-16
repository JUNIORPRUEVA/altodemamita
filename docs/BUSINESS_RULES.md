# Sistema Solares Business Rules

## Scope

This document records current business rules from audits. It does not define new target behavior unless explicitly labeled.

## Lot Rules

Lot states:

- `disponible`
- `reservado`
- `vendido`

A lot can be selected for a new sale only when it is `disponible`.

The system blocks duplicate active lots with the same block and lot number.

When a sale is `apartado` or `inicial_incompleto`, the lot is normally `reservado`.

When a sale is `activa` or `pagada`, the lot is normally `vendido`.

## Sale Rules

Sale states:

- `apartado`
- `inicial_incompleto`
- `activa`
- `pagada`
- `cancelada`

A new sale requires an existing client, lot, user, and optionally seller.

The system blocks more than one active sale for the same lot.

Initial payment and reserve fields affect whether the sale stays in reserve/incomplete state or becomes active.

Server-authoritative sale creation foundation is implemented locally in Phase 1D. It preserves the local rule that an `apartado` amount does not count as paid initial; the required initial remains pending until a later upfront payment completes it.

## Current Cancellation Behavior

CURRENT BEHAVIOR - REQUIRES BUSINESS REVIEW.

Cancelling/deleting a sale currently:

- soft-deletes active payments for the sale
- soft-deletes active installments for the sale
- sets the sale to `cancelada`
- sets `ventas.deleted_at`
- may soft-delete the linked lot when no other active sale exists for that lot

This behavior must not be silently corrected. A future phase must get business approval for the intended rule.

## Installment Rules

Installment states:

- `pendiente`
- `vencida` (derived at read time from the business date; see "Persisted versus effective status")
- `parcial`
- `pagada`
- `ajustada`
- `cancelada`

Installments are generated from financed balance, monthly interest, installment count, and due dates.

An installment is considered paid when paid amount is within tolerance of the total amount.

### Canonical calendar anchor (P0 hardening, 2026-09-16)

`dueDate(n) = Sale.saleDate + n calendar months`, for `n = 1..installmentCount`.

- `Sale.saleDate` is the ONLY calendar anchor.
- `Sale.activationDate` is the date the sale became active / the initial payment was applied.
  It has its own meaning and MUST NOT move the schedule. It may legitimately differ from
  `saleDate` (for example sale 2026-07-15 with the initial paid 2026-08-15) without changing
  any installment due date.
- Registering or completing the initial payment later NEVER regenerates, shifts, adds another
  month to, or recreates existing installments.
- Month semantics: add the calendar month keeping the original time of day; when the target day
  does not exist, clamp to the last day of the target month (2026-01-31 + 1 month = 2026-02-28;
  2028-01-31 + 1 month = 2028-02-29; 2026-03-30 + 1 month = 2026-04-30).
- The backend is authoritative: it generates the schedule, or it rejects a client-supplied
  schedule that does not satisfy the rule (`installment_due_date_not_canonical`). It never
  silently rewrites an ambiguous financial payload.
- Once created, `dueDate`, `installmentNumber`, `openingBalance`, `principalAmount`,
  `interestAmount`, `totalAmount`, `endingBalance` and the sale anchor are server-owned: a
  legacy/offline upload cannot overwrite them (`installment_field_locked`). Changing them
  requires an explicit authorized operation.

### Persisted versus effective status

- The `status` column stores only what depends on money or a terminal state: `pagada` (fully
  covered), `parcial` (partial payment), `pendiente` (no payment), plus the terminal
  `ajustada` / `cancelada`.
- `vencida` is an EFFECTIVE status: it is derived at read time from `dueDate` and the business
  date. It is never persisted, so the natural passing of a day does not produce a write and the
  historical status is not rewritten.
- The business date is always `America/Santo_Domingo` (UTC-4, no DST). The equipment timezone is
  never authoritative, and SQLite `date('now')` (UTC) must not be used for business logic:
  it advances the day at 20:00 Dominican time.

## Payment Rules

Payment types:

- `apartado`
- `abono_inicial`
- `cuota`
- `abono_capital`

UI selection modes can include `cuota_vencida` and `todas_cuotas_vencidas`.

Installment payment application is interest-first, then principal.

Capital prepayment is blocked if the sale has a pending initial payment.

Capital prepayment is blocked if the sale has overdue installments.

Only the latest active payment for a sale can be annulled.

Payment annulment soft-deletes the payment and recalculates sale/installment state.

Server-authoritative payment registration foundation is implemented locally in Phase 1D. It supports upfront payments, installment payments, overdue installment batch selection, capital prepayment, and latest active payment annulment. Sale cancellation remains deferred pending business approval.

Phase 1F UAT correction: server capital prepayment recalculation must not create or lose principal. After a valid `abono_capital`, `Sale.balance` must equal the sum of remaining active installment principal within current currency tolerance.

Phase 1F cancellation V1: server-authoritative cancellation blocks sales with active/non-annulled payments that require reversal. Clean cancellation marks the sale cancelled, marks remaining installments cancelled without hard deletion, restores the lot to `disponible`, and preserves history. Lots must never be hard-deleted by cancellation.

## Financial Rules

Currency calculations currently round to 2 decimals using the local helper logic.

Sale pending balance is reconciled from non-deleted, non-adjusted installment principal remaining:

```text
SUM(MAX(capital_cuota - capital_pagado, 0))
```

Balances at or below approximately `0.009` are treated as paid/zero.

## Sync And Offline Rules

Current local app writes business operations locally first, then queues sync.

Target offline behavior must be idempotent and durable.

The offline outbox must survive restart, app update, network loss, and backend outage.

Cache cleanup must never delete pending outbox operations.
