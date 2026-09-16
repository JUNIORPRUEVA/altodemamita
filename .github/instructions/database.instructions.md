---
description: "Use when editing the database schema, migrations, seeds, or data scripts of this repository. Covers migration safety, backward compatibility, destructive-operation authorization, and drift handling."
applyTo: "backend/prisma/**"
---

# Database rules

Installed because this repository has schema/migration files at `backend/prisma`.

## Before changing the schema

1. Read the project's architecture/data document (`AGENTS.md` routes it).
2. Find the code that reads and writes the affected tables, and the clients that consume the affected API responses.
3. Confirm backward compatibility: new columns need defaults or nullable handling so existing rows, existing clients, and cached payloads keep working.
4. Confirm the project's scoping rule (tenant/company/owner) is preserved, and that new unique constraints cannot collide across scopes.
5. Prefer additive changes. Renames and type changes need an explicit migration plan.

## Commands (verify before use)

| Action | Command | Working directory |
| --- | --- | --- |
| Validate schema | `npx prisma validate` | `backend/prisma` |
| Generate client | `npx prisma generate` | `backend/prisma` |
| Create migration (local/dev) | `TODO (restricted - verify)` | `backend/prisma` |
| Apply migrations | `TODO (restricted - verify)` | `backend/prisma` |
| Seed | `TODO (restricted - verify)` | `backend/prisma` |

`TODO (restricted - verify)` and `TODO (restricted - verify)` are **restricted**: they require explicit authorization, and they are never pointed at a shared, staging, UAT, or production database by default.

## Migration safety

- Never edit an already-applied migration in a shared database; add a new migration.
- Never resolve drift by deleting a database, dropping or truncating tables, or mass `DELETE`/`UPDATE`. Diagnose and report first.
- Back up before any authorized migration on a shared environment.
- Review the migration file for: data loss, locking behavior, long-running operations, missing indexes, and rollback feasibility.
- State in the task report whether the migration is reversible and what it does to existing data.

## Seeds and data scripts

- Seeds are for local/dev/UAT only, and they must be idempotent.
- Purge, repair, fix, backfill, and `--apply` scripts require explicit authorization in the current task, always with a dry-run first when the script supports it.
- Never put real production data, credentials, or dumps into the repository.

## Naming and consistency

- Follow the project's existing naming conventions for models, tables, columns, and indexes.
- Keep relations and delete behavior explicit; do not rely on cascade surprises.
- If a documented model and the real database disagree (drift), report the discrepancy instead of editing history.
