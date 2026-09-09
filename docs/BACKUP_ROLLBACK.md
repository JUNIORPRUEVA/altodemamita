# Backup And Rollback

Status: documentation only.

## Current SQLite Production Backup

The current production SQLite database is business evidence before cutover. Customer original SQLite files must be preserved unchanged.

SQLite backups taken before migration must be stored separately from future cache backups. They are rollback and audit evidence.

## Production Acquisition Rules

Customer production DB is NOT on this development PC. Development DB files are not production evidence.

Before copying production data:

1. The customer application MUST be fully closed.
2. Confirm no Sistema Solares process is running.
3. DO NOT launch the application before acquisition completes.
4. Copy `sistema_solares.db`.
5. Also copy sidecars from the same acquisition window when present:
   - `sistema_solares.db-wal`
   - `sistema_solares.db-shm`
   - `sistema_solares.db-journal`
6. Keep DB and sidecars together.
7. Preserve original customer files untouched.
8. Inspect ONLY the copy.
9. Determine `PRAGMA user_version` only on the copy.
10. Hash copied artifacts where appropriate.

Rollback evidence starts with the untouched original customer files plus the verified acquisition copy.

## Future PostgreSQL Backup

After cloud cutover, PostgreSQL is the business source of truth. PostgreSQL backups become the business backup.

Required future backup areas:

- PostgreSQL database backup
- restore validation
- point-in-time recovery strategy, if available
- application version associated with backup
- migration/cutover evidence
- document/media storage backup if cloud documents/media become authoritative

## Local Cache Backup After Cutover

Do not use local cache backup as business backup after cutover. A cache is disposable and may be incomplete, stale, or rebuilt from the server.

## Rollback Evidence

Rollback evidence must include:

- customer original SQLite
- safe migration copy
- copied sidecars from the same acquisition window when present
- source SHA256 before and after migration attempt
- working copy SHA256 before and after any repair
- repair action list, such as working-copy-only `REINDEX`
- migration logs
- validation results
- reconciliation results
- application test results
- cutover approval

The hardened migration tool writes both `customer_migration_report.json` and `customer_migration_report.md`. Preserve both with the safe copy and PostgreSQL migration logs.

If migration fails before cutover, the customer original SQLite remains the rollback authority. If cutover has already occurred in a future approved phase, rollback must use the approved PostgreSQL backup/restore procedure; local cache files are not business rollback evidence.

## 2026-09-08 Production Pre-Deploy Backup

Before deploying backend image `altomamita_altomamita-backend:prod-finalization-20260908T201059Z`, production PostgreSQL was backed up to:

```text
/etc/easypanel/projects/altomamita/backups/pre-deployment/altomamita_predeploy_20260908T201049Z.dump
SHA256=d304870c66d4de7281596a3e1be0285ab5efda19eaf4d6b80714d6f0354b6bf8
SIZE=73951
```

`pg_restore -l` succeeded for this dump. Backend rollback image is `altomamita_altomamita-backend:prod-shell-phase1f-20260908`.

## 2026-09-08 Production Cutover Backups And Infra Snapshot

Verified PostgreSQL dump evidence:

```text
/etc/easypanel/projects/altomamita/backups/pre-migration/altomamita_premigration_20260908T205640Z.dump
SHA256=041050bef9d3d972244ac429d61bb880421711405e6df919ed10e482e66c2eb5
SIZE=73963

/etc/easypanel/projects/altomamita/backups/post-cutover/altomamita_postcutover_20260908T220026Z.dump
SHA256=99fac2a98c07480daa4d6e50cbb65b532ad1d6b8d5465857308a448d3d685f3f
SIZE=1966899
```

Production EasyPanel infrastructure snapshot:

```text
/root/altomamita_infra_snapshot_20260908T224029Z
```

Backup policy file on the server:

```text
/etc/easypanel/projects/altomamita/backups/BACKUP_POLICY.md
```

EasyPanel local backup providers exist at `/etc/easypanel/backups`. A native EasyPanel scheduled database backup for `altomamita` was not enabled or verified during the infrastructure normalization. Until that is configured through an approved EasyPanel-native procedure, retain the verified manual dumps and infra snapshot as rollback evidence.
