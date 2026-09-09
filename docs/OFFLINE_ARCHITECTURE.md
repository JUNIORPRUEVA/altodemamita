# Offline Architecture

Status: Phase 2 local foundation implemented. This is not production cutover.

## Target Local Layout

Future local persistence should be split by responsibility:

- `cache.db`
- `outbox.db`
- `device_state.db`

Phase 2 creates and migrates these local foundation databases under the Windows app support root. Legacy SQLite remains the default business source in `LEGACY_LOCAL` mode.

## Phase 2 Client Guardrails

`CLOUD_CUTOVER_MODE` defaults to `LEGACY_LOCAL`. Authoritative cloud operation enqueueing is available only in `CLOUD_UAT` or `CLOUD_AUTHORITATIVE`.

In cloud cutover modes, legacy SQLite sync of `sales`, `installments`, and `payments` is blocked client-side so the client cannot dual-write financial scopes through the old sync channel while also using authoritative sale/payment operations.

## cache.db

`cache.db` contains a local projection of cloud-authoritative business data. It is disposable and rebuildable from the server.

If `cache.db` is corrupted or deleted, the app should recover by downloading fresh cloud state. It must not be the only business backup after cutover.

## outbox.db

`outbox.db` contains durable pending operations that have not been safely accepted by the server.

The outbox must survive:

- app restart
- Windows restart
- network failure
- backend outage
- app upgrade

Stable operation identity is mandatory. A retry after timeout must map to the same server operation, not create a duplicate sale, duplicate payment, or duplicate mutation.

## device_state.db

`device_state.db` contains device-local state:

- device identity
- local sync cursors
- local auth/session cache
- feature/runtime flags
- last sync diagnostics
- local printer preferences when stored in SQLite

This data is not the business source of truth.

## Current Versus Target

Current local SQLite combines business source data, sync state, auth/session state, configuration, backup metadata, and outbox/conflict state. The target separates these concerns so cloud-authoritative data can be rebuilt safely while durable local operations are preserved.
