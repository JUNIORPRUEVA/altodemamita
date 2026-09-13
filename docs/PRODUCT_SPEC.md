# Sistema Solares Product Spec

## Product Scope

Sistema Solares manages a single company's lot sales operation. It supports clients, lots, sellers, sales, reserves, initial payments, financing, installments, payments, capital prepayments, payment annulment, sale cancellation, users, permissions, PDFs, printing, backups, and an owner app.

This document describes evidence-supported current behavior. It does not claim target behavior is implemented.

## Clients

Clients are stored locally in `clientes`.

Supported fields include name, document ID (`cedula`), phone, address, timestamps, soft delete, and sync metadata.

Current behavior validates duplicate active document IDs and phone numbers. Deleting a client is blocked when the client has an active sale. Deleted clients are soft-deleted with `deleted_at`; the document may be rewritten to a `__DELETED__` placeholder to preserve uniqueness.

## Lots

Lots are stored locally in `solares`.

Core fields are block number (`manzana_numero`), lot number (`solar_numero`), area, price per meter, status, timestamps, soft delete, and sync metadata.

Lot states are:

- `disponible`
- `reservado`
- `vendido`

The system blocks duplicate active lots for the same block and lot number.

## Sellers

Sellers are stored in `vendedores`.

Core fields include name, document ID, phone, timestamps, soft delete, and sync metadata.

## Sales

Sales are stored in `ventas`.

A sale links a client, lot, user, and optionally seller. A sale records sale price, required initial payment, paid initial payment, reserve amount, financed balance, pending balance, monthly interest, installment count, dates, status, and sync metadata.

Current sale states include:

- `apartado`
- `inicial_incompleto`
- `activa`
- `pagada`
- `cancelada`

A sale can be created only when the selected lot is `disponible` and no active sale exists for the same lot.

## Reserves And Initial Payments

Reserve/initial flows use sale statuses `apartado` and `inicial_incompleto` until the required initial amount is completed.

When the initial requirement is completed, the sale can become `activa`, generated installments are created, and the lot becomes `vendido`.

## Financing And Installments

Installments are stored in `cuotas`.

Installments include opening balance, principal, interest, total amount, paid amount, paid principal, paid interest, ending balance, status, timestamps, and sync metadata.

Installment states include:

- `pendiente`
- `vencida`
- `parcial`
- `pagada`
- `ajustada`
- `cancelada`

Financing uses a fixed payment calculation. Currency rounding is to 2 decimals using `(value * 100).roundToDouble() / 100`.

## Payments

Payments are stored in `pagos`.

Payment types include:

- `apartado`
- `abono_inicial`
- `cuota`
- `abono_capital`

The UI also uses payment choices such as `cuota_vencida` and `todas_cuotas_vencidas` to select which installments are affected.

Installment payments apply interest first and then principal. Capital prepayment is blocked when an initial payment is pending or overdue installments exist.

Only the latest active payment of a sale can be annulled. Annulment soft-deletes the payment and recalculates affected sale/installment state.

## Sale Cancellation

Cancelling/deleting a sale soft-deletes the sale, its payments, and installments.

CURRENT BEHAVIOR - REQUIRES BUSINESS REVIEW: current code can soft-delete the linked lot when no other active sale exists for that lot. This must not be silently corrected without business approval.

## Users, Roles, And Permissions

The local app has users, roles, role assignments, permissions, sessions, password hashes, recovery credentials, and offline login support. Cloud/server-side RBAC is not complete enough to be called authoritative.

## PDFs And Printing

The local app generates PDF documents for sale initial receipts, amortization tables, payment receipts, and client reports/pagares. PDFs are generated on demand and can be printed or shared through the Flutter printing stack.

## Backups

Current backups are local-authoritative and can package the SQLite DB, config files, generated files, and a manifest. Professional local backups copy the DB into a configured backup directory.

After cloud cutover, local backup is not the primary business backup.

## Owner App

`app_owner` is the owner's mobile app for Android APK and iPhone builds. It must open directly to `Resumen`; it must not expose a visible login screen, email field, or password field. The app consumes backend APIs through a configured/stored owner session and keeps an owner snapshot cache for faster loading. The owner cache is not authoritative business storage.

`app_local` is the Windows administrative app. Do not modify `app_local` for owner mobile experience changes unless a later approved phase explicitly requests it.
