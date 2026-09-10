# SISTEMA SOLARES - NOTIFICATION AUDIT

Date: 2026-09-09

## Existing System

EXISTING SYSTEM FOUND: YES

Current channel: WhatsApp template messages.

Current provider: Meta WhatsApp Cloud API via `https://graph.facebook.com/v20.0/{WHATSAPP_PHONE_NUMBER_ID}/messages`.

Current execution location: backend process. `server.ts` calls `startPaymentReminderJob()` after boot.

Current data source: PostgreSQL through Prisma models `Sale`, `Client`, `Lot`, `Installment`, `Payment`, `PaymentReminderNotification`, `PaymentReminderDelivery`, and `LateFeeSnapshot`.

Windows PC required: NO for scheduled cloud-side reminders.

## Map

TRIGGER:

- Manual sale summary: `GET /payment-reminders/sales/:saleSyncId/overdue-summary`.
- Manual send/dry-run: `POST /payment-reminders/sales/:saleSyncId/send`, OWNER only.
- Manual company run: `POST /payment-reminders/run`, OWNER only.
- Automatic backend job: `startPaymentReminderJob()`.

SCHEDULER:

- `backend/src/jobs/paymentReminder.job.ts`.
- Simple daily cron syntax only, default `0 9 * * *`.
- Dominican timezone gate uses `America/Santo_Domingo`.
- Window default: Monday-Saturday, 09:00-17:00.

QUERY:

- `PaymentReminderService.processCompany()` scans active company sales.
- `getSaleSummary()` re-reads the sale, client, lot, installments, payments, and last notification from PostgreSQL.
- Terminal sale statuses are skipped: `pagada`, `cancelada`, `anulada`, `cerrada`, `saldada`.
- Installments are included when overdue, unpaid, not deleted, and not `pagada`, `cancelada`, or `ajustada`.

TEMPLATE:

- Base default: `recordatorio_cuotas_vencidas_profesional5`.
- Template families exist for project, detailed, elegant, and professional variants.
- The service chooses 1-5 installment templates based on overdue installment count.
- Templates with fixed capacity skip events that exceed capacity.

PROVIDER:

- `WhatsappService.sendTemplateMessage()`.
- Requires `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_BUSINESS_ACCOUNT_ID` only when real delivery is enabled and dry-run is off.
- Webhook status updates are handled at `/payment-reminders/whatsapp/webhook`.

DELIVERY:

- Production delivery is blocked unless all safety flags allow it.
- Test mode redirects to configured test numbers.
- Real recipient mode requires `PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS=true`.

LOG/AUDIT:

- `PaymentReminderNotification` stores the logical event.
- `PaymentReminderDelivery` stores per-recipient delivery state.
- `LateFeeSnapshot` stores per-installment late-fee calculation evidence.

## Why Disabled

Production public status on 2026-09-09 reported:

- `enabled=false`
- `emergencyStop=true`
- `dryRun=true`
- `testMode=true`
- `allowRealRecipients=false`

Therefore production notifications are disabled by explicit feature flags and emergency stop. This is correct for audit mode.

Local development `.env` contains real-delivery-shaped flags and provider credentials. Do not rely on that local file for activation safety; rotate any exposed provider token before production activation.

## Business Rules Found

Implemented notification type:

- `OVERDUE_INSTALLMENTS`

Trigger:

- A sale has one or more overdue installments with remaining amount.

Recipient:

- Client phone from PostgreSQL `Client.phone`, normalized for Dominican WhatsApp numbers.

Timing:

- Daily backend scheduler, constrained to the Dominican send window.

Frequency / dedupe:

- Unique logical key: `companyId + saleSyncId + type + lastOverdueInstallmentSyncId`.
- A repeated run for the same latest overdue installment is skipped unless forced.

Stop condition:

- No overdue unpaid installments, terminal sale, invalid/blocked recipient, template over capacity, unapproved template, duplicate logical event, or global safety switch.

Payment received message:

- NOT IMPLEMENTED as a general payment confirmation system.
- Existing scripts/routes are for overdue payment reminders only.

## Cloud Migration Impact

PostgreSQL cloud ready for reminder reads: PASS, based on current source.

No old local SQLite scheduling dependency was found in notification code.

Remaining caveats:

- Automatic scheduler is in the backend web process, not a separate durable worker.
- Delivery retry exists only as reprocessing of failed delivery rows under forced/manual paths; no bounded backoff worker was found.
- Dry-run audit persistence was incomplete before this audit and has been added locally.

## Safety Fix Applied Locally

`PaymentReminderService.sendSaleReminder()` now persists dry-run audit rows:

- `PaymentReminderNotification.status = DRY_RUN`
- `PaymentReminderDelivery.status = DRY_RUN`
- `LateFeeSnapshot.eventType = DRY_RUN`

Dry-run still does not call WhatsApp.

A repeated dry-run for the same logical event now returns `SKIPPED_DUPLICATE`, preserving exactly one logical audit event unless `force=true` is explicitly used.

`processCompany()` now separates `dryRun` count from `sent`.

## Template Message Correction

CURRENT TEMPLATE:

- `recordatorio_cuotas_vencidas_profesional5`
- Current backend also supports `profesional1` through `profesional5`, `elegante1` through `elegante5`, and `detalle1` through `detalle5`.
- The provider channel is Meta WhatsApp approved templates, not free-form messages.

ROOT PROBLEM:

- The backend already selected the `profesional5` family member when a client had more than five overdue installments.
- After that, it blocked the send/dry-run because the selected template capacity was five.
- Result: clients with more than five overdue installments were skipped instead of receiving a complete-total reminder.

CORRECTION:

- Keep the visual limit at five installments.
- For more than five installments, render the first five visible installments and append an additional-count note to the fifth visible line/month parameter.
- The final total still uses `summary.totalGeneral`, which includes all overdue installments, including hidden ones.
- Partial payments continue to use `saldoPendiente`, not the original installment amount.
- Test-mode preview now formats due dates as `DD/MM/YYYY` instead of ISO date keys.

MAX INSTALLMENTS DISPLAYED: 5

TOTAL OVERDUE CALCULATION: PASS

>5 INSTALLMENTS: PASS

PARTIAL PAYMENT: PASS

ALREADY PAID SUPPRESSION: PASS

INVALID PHONE: PASS

META TEMPLATE APPROVAL REQUIRED:

- NO for this backend variable-shaping fix if the existing Meta template text and variable count remain unchanged.
- YES if the operator wants to change the approved WhatsApp template body itself to one of the proposed final message wordings below.

## Message Options

All options use the same financial data. Recommended default: A.

MESSAGE OPTION A - PROFESIONAL Y CORTA:

```text
Hola, [Nombre]. Te recordamos que tienes [Cantidad] cuota(s) vencida(s) correspondiente(s) a tu solar [Solar].

[Detalle de cuotas]

Total vencido: [Total vencido]
Balance pendiente: [Balance pendiente]
Fecha de corte: [Fecha]

Gracias por ponerte al dia. [Negocio]
```

MESSAGE OPTION B - CORDIAL / CERCANA:

```text
Hola, [Nombre]. Esperamos que estes bien. Te compartimos un recordatorio de los pagos pendientes de tu solar [Solar].

[Detalle de cuotas]

Total vencido: [Total vencido]
Balance pendiente: [Balance pendiente]
Fecha de corte: [Fecha]

Para cualquier consulta, estamos a la orden. [Negocio]
```

MESSAGE OPTION C - MAS FORMAL ADMINISTRATIVA:

```text
Saludos, [Nombre]. Segun nuestros registros, tu solar [Solar] presenta [Cantidad] cuota(s) vencida(s).

[Detalle de cuotas]

Total vencido: [Total vencido]
Balance pendiente: [Balance pendiente]
Fecha de corte: [Fecha]

Favor tomarlo como recordatorio administrativo. [Negocio]
```

RECOMMENDED MESSAGE:

- Option A, because it is clear, short, non-aggressive, and suitable for WhatsApp.
- Use the configured business identity from `COMPANY_NAME` / `CompanyProfile`; do not hardcode a new commercial name.

## Render Examples

These examples are dry-run style previews. No real phone number is shown.

DRY-RUN 1 INSTALLMENT:

```text
Recipient: ***1234
Template: recordatorio_cuotas_vencidas_profesional1

Solar: MM-H-S88
Enero 2026
Cuota vencida: RD$10,000.00
Mora: RD$300.00
Total vencido: RD$10,300.00
```

DRY-RUN 5 INSTALLMENTS:

```text
Recipient: ***1234
Template: recordatorio_cuotas_vencidas_profesional5

Solar: MM-H-S88
Enero 2026 - RD$10,000.00 - mora RD$300.00
Febrero 2026 - RD$10,000.00 - mora RD$300.00
Marzo 2026 - RD$10,000.00 - mora RD$300.00
Abril 2026 - RD$10,000.00 - mora RD$300.00
Mayo 2026 - RD$10,000.00 - mora RD$300.00
Total vencido: RD$51,500.00
```

DRY-RUN 8 INSTALLMENTS:

```text
Recipient: ***1234
Template: recordatorio_cuotas_vencidas_profesional5

Solar: MM-H-S88
Enero 2026 - RD$10,000.00 - mora RD$300.00
Febrero 2026 - RD$10,000.00 - mora RD$300.00
Marzo 2026 - RD$10,000.00 - mora RD$300.00
Abril 2026 - RD$10,000.00 - mora RD$300.00
Mayo 2026 y 3 cuotas adicionales vencidas. - RD$10,000.00 - mora RD$300.00
Total vencido: RD$82,400.00
```

DRY-RUN PARTIAL:

```text
Recipient: ***1234
Template: recordatorio_cuotas_vencidas_profesional1

Solar: MM-H-S88
Enero 2026
Restante vencido: RD$3,500.25
Mora: RD$300.00
Total vencido: RD$3,800.25
```

DRY-RUN ALREADY PAID:

```text
Status: SKIPPED_NO_OVERDUE
Reason: the overdue installment was fully paid before rendering.
```

## Production Counts

Read-only PostgreSQL audit query run on 2026-09-09:

- due soon: not implemented, 0
- due today sales: 5
- overdue sales: 72
- overdue with valid Dominican WhatsApp-format phone: 53
- overdue invalid/no phone: 19
- overdue exceeding current 5-installment template capacity: 6
- overdue not previously logged: 72
- existing notification rows: 0
- existing delivery rows: 0

REAL CUSTOMER MESSAGES SENT: 0

PRODUCTION DB MUTATIONS: 0

## Test Evidence

Backend build: PASS

Command:

```powershell
cd backend
npm run build
```

Backend tests: PASS, 64 tests

Command:

```powershell
cd backend
npm test
```

New focused coverage:

- dry-run persists notification, delivery, and snapshot audit rows
- duplicate dry-run is skipped by the stable logical key
- WhatsApp is not called during dry-run

Existing focused coverage includes:

- overdue calculation
- paid/future/today suppression
- late-fee timezone/day behavior
- template rendering
- test recipient redirection
- real-recipient blocking
- Dominican phone normalization
- send window gating

## Final Status

POSTGRESQL CLOUD READY: PASS for reminder reads.

SERVER-SIDE SCHEDULER: PASS with caveat: runs in backend process, not a separate durable worker.

WINDOWS PC REQUIRED: NO.

DUE REMINDER: NOT IMPLEMENTED; due-today is explicitly excluded from overdue reminders.

OVERDUE: PASS.

PAYMENT CONFIRMATION: NOT IMPLEMENTED.

DEDUPLICATION: PASS for logical overdue reminder events.

RETRY: PARTIAL; failed delivery state exists, but no bounded backoff worker was found.

TIMEZONE: PASS; configured and validated as `America/Santo_Domingo`.

PHONE VALIDATION: PASS for Dominican WhatsApp numbers; non-Dominican numbers are currently rejected.

DELIVERY LOG: PASS.

GLOBAL KILL SWITCH: PASS via `PAYMENT_REMINDERS_ENABLED` and `PAYMENT_REMINDERS_EMERGENCY_STOP`.

DRY RUN: PASS locally after this audit change; not yet deployed.

SAFE TO ACTIVATE: NO-GO until explicit operator GO, token rotation/reverification, dry-run deployment, monitored dry-run, and one operator-controlled test delivery.

PRODUCTION NOTIFICATIONS: KEEP DISABLED.

## Activation Plan

1. Rotate WhatsApp/Meta token if any local secret was exposed.
2. Deploy the dry-run audit persistence change.
3. Confirm production remains `PAYMENT_REMINDERS_ENABLED=false`, `PAYMENT_REMINDERS_EMERGENCY_STOP=true`, `PAYMENT_REMINDERS_DRY_RUN=true`, `PAYMENT_REMINDERS_TEST_MODE=true`, `PAYMENT_REMINDERS_ALLOW_REAL_RECIPIENTS=false`.
4. Run read-only production counts again.
5. Temporarily allow only OWNER-triggered dry-run, still with emergency stop policy reviewed.
6. Run manual dry-run and inspect `PaymentReminderNotification`, `PaymentReminderDelivery`, and `LateFeeSnapshot`.
7. Verify template approval and phone number status with Meta without printing secrets.
8. With explicit operator GO, run one test message to an operator-controlled test recipient only.
9. Monitor webhook delivery/read/failure updates.
10. Only after business GO, disable dry-run and real-recipient block in a limited canary.
11. Monitor failures, duplicates, complaints, and provider rate limits.
12. Roll back by setting `PAYMENT_REMINDERS_EMERGENCY_STOP=true`.
