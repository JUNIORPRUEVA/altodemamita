# Windows Storage

Status: current source evidence plus target storage documentation. This document does not implement storage changes.

## Current Install Roots

Current per-user install root:

```text
%LOCALAPPDATA%\Programs\Sistema Solares
```

Current managed/all-users install root:

```text
%ProgramFiles%\Sistema Solares
```

The installer owns application binaries and immutable packaged assets under the install root. Runtime writes must not depend on write access to the install root.

## Current Mutable Support Root

Current writable runtime support root:

```text
%LOCALAPPDATA%\SistemaSolares
```

Current DB path:

```text
%LOCALAPPDATA%\SistemaSolares\data\database\sistema_solares.db
```

Current additional mutable paths include:

- `data`
- `data\database`
- `config`
- `logs`
- `logs\incidents`
- `backups`
- `generated`
- `media`
- `recovery`
- `recovery\quarantine`
- `recovery\snapshots`
- `cache`
- `temp`

Current fallback behavior may use `%APPDATA%\SistemaSolares` or user-profile application data locations when `%LOCALAPPDATA%` is unavailable. Current backup configuration/history has legacy paths under the legacy support directory.

Current professional local backup defaults may use an external/preferred backup location such as `D:\FULLPOS_BACKUPS` when available, or a user Documents fallback. These backup paths are local operational paths, not future cloud-authoritative business storage.

## Device-Local Classification

DEVICE-LOCAL current/target data includes:

- `configuracion_impresoras`
- printer selection and device settings
- local sync cursors
- device identity
- local session/cache
- backup preferences and backup history
- technical logs
- durable outbox
- conflict technical state

Cloud-business target data includes company/business profile, business contact/logo metadata where authoritative, financial parameters, business-global configuration, and users/roles/permissions required for business authorization.

## Target Mutable Tree

PHASE 2 LOCAL FOUNDATION IMPLEMENTED:

```text
%LOCALAPPDATA%\SistemaSolares
  data
    cache
      cache.db
    outbox
      outbox.db
    state
      device_state.db
  config
  logs
  backups
    local
  generated
  media
  recovery
  migration
  temp
```

`data\cache\cache.db`, `data\outbox\outbox.db`, and `data\state\device_state.db` now exist as Phase 2 local foundation storage in `app_local`. This does not make cloud cutover complete: `cache.db` is rebuildable projection storage, `outbox.db` is durable pending operation storage, and `device_state.db` is device-local state.

## Permission Reasoning

Writable runtime data must not be placed in `%ProgramFiles%`. Managed install directories can require elevated permissions, can be protected by Windows security policy, and can block normal user writes.

The application binary and immutable assets belong under the install root. Databases, queues, logs, generated reports, media, backups, recovery data, migration artifacts, and temporary files belong under `%LOCALAPPDATA%\SistemaSolares` or approved external backup locations.
