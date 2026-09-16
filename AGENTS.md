# Sistema Solares Agent Instructions

This file is mandatory for every future Codex session in this repository.

## Before Any Change

1. Read `AGENTS.md`.
2. Read `docs/PRODUCT_SPEC.md`.
3. Read `docs/ARCHITECTURE.md`.
4. Read `docs/DATA_MODEL.md`.
5. Read `docs/BUSINESS_RULES.md`.
6. Read `docs/PROJECT_STATUS.md`.
7. Read `docs/CLOUD_ARCHITECTURE.md`.
8. Read `docs/OFFLINE_ARCHITECTURE.md`.
9. Read `docs/DATA_MIGRATION.md`.
10. Read `docs/API_CONTRACTS.md`.
11. Read `docs/TESTING.md`.
12. Read `docs/BACKUP_ROLLBACK.md`.
13. Read `docs/WINDOWS_STORAGE.md`.
14. Read `docs/OPERATIONS_RUNBOOK.md`.
15. Read `docs/DECISIONS.md`.
16. Read `docs/ENVIRONMENTS.md`.
17. Read any other phase-specific docs only after the baseline above.
18. Run `git status`.

Legacy docs under `docs/sync`, `docs/audit`, or other historical folders preserve useful history, but they MUST NOT override the current baseline documentation. When conflict exists, CURRENT BASELINE DOCS + SOURCE EVIDENCE WIN.

## Non-Negotiable Rules

- Sistema Solares is a SINGLE-COMPANY system.
- Do not invent multi-tenancy.
- Existing `Company`, `companyId`, and `tenantKey` are a FIXED SINGLE-COMPANY NAMESPACE - LEGACY CURRENT IMPLEMENTATION.
- Do not remove `Company`, `companyId`, or `tenantKey` unless a later approved phase explicitly does it.
- Never treat DEV SQLite as customer production.
- Customer production DB lives on the customer's PC.
- Migration work must use a verified COPY of the customer DB, not the live file.
- Before acquiring production data, the customer app must be fully closed, no Sistema Solares process may be running, and the app must not be launched again until acquisition is complete.
- Copy `sistema_solares.db` and, when present in the same acquisition window, `sistema_solares.db-wal`, `sistema_solares.db-shm`, and `sistema_solares.db-journal`.
- Inspect and hash only the copied production artifacts; preserve original customer files untouched.
- PostgreSQL target = source of truth.
- Local DB target = cache, outbox, and device state only.
- No financial data loss.
- No duplicate payment.
- No duplicate active sale for the same lot.
- Offline operation must be idempotent.
- Outbox must survive restart, update, and network/backend failure.
- Audit before modifying.
- Work by phases.
- Every phase ends with tests, risks, and GO/NO-GO.
- Never silently rewrite historical production data.
- Never claim TARGET behavior is already implemented.

## Current Reality

Current operational source is `app_local` + SQLite (`sistema_solares.db`).

The backend is Express + TypeScript + Prisma + PostgreSQL. Current cloud data is not authoritative enough for production.

## Target Direction

PostgreSQL cloud becomes the authoritative business database.

TARGET ARCHITECTURE REQUIREMENT - NOT IMPLEMENTED YET: backend owns validation, financial rules, transactions, idempotency, concurrency protection, and permissions.

Current backend does not yet fully satisfy those guarantees.

Windows local storage becomes cache, durable offline outbox, device state, config, logs, and support/recovery files.


<!-- The block below is generated. The content above is project-owned and was NOT modified. -->
<!-- AI-GOVERNANCE:BEGIN global-agent-policy v1 -->
<!-- GENERATED FROM AI-GOVERNANCE - DO NOT EDIT THIS SECTION MANUALLY.
     Source: C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md
     Regenerate: Sync-AgentPolicy.ps1 -Project SistemaSolares -Mode Apply -->

**This project follows the AI Agent Governance System.** Full policy: `C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md`.

**Before editing**

1. Identify the correct repository root, current branch, and worktree.
2. Run `git status --short`; never start on top of unexplained changes.
3. Read the project documentation that applies, and the real code of the area you will touch.
4. Restate the requirement and its acceptance criteria; confirm the smallest change that satisfies it.
5. If the request is an audit: report with evidence, change nothing.

**Parallel work**

- Multiple agents are allowed. **One writer per worktree.** A writing agent uses its own worktree + its own `agent/<task>` branch.
- Read-only agents (audit/review) may run in parallel anywhere.
- If another agent may be writing in the same working tree: **STOP**, do not edit, report `CONCURRENT WRITER RISK`.

**Implementation**

- Minimum change that satisfies the request; no unrelated refactors, no renames for taste.
- Fix the root cause; never hide a symptom with a patch or a forced refresh.
- Do not invent facts, endpoints, models, commands, test results, or documentation. Distinguish **FACT** (verified), **HYPOTHESIS** (plausible, unverified), **RECOMMENDATION** (proposal).
- Preserve compatibility when compatibility is a requirement (existing data, clients, caches).
- Stay inside the task scope; report unrelated findings instead of fixing them silently.

**Security**

- Never print, log, or commit secrets: passwords, tokens, API keys, private keys, credentials, real `.env` values.
- No production access by default. Production is **read-only** unless the current task explicitly authorizes more.
- Destructive operations need explicit authorization in the current task: deploy, migration, seed, mass update/delete, service restart, infrastructure or DNS change, license change.

**Validation (compilation alone is not completion)**

- Review the final diff: no debug leftovers, no temporary TODOs, no out-of-scope edits, no secrets.
- Run static analysis and build for the modified area; run the tests closest to the change.
- Functional verification for behavior changes; visual verification when UI changed.
- Regression checks for high-risk areas (auth, payments, cash, inventory, accounting, permissions, tenants, migrations, sync, release).
- Report failures that you did not cause, with evidence. Never hide a failing check.

**Definition of Done**

- Requirement fully covered, item by item.
- Scope respected; diff reviewed.
- Analysis/build/tests pass on the modified area.
- Validation actually executed (not assumed); blocked validation reported as blocked.
- Risks and pending items documented.

**Final verdict**

- `GO` — everything above is true.
- `GO WITH ISSUES` — usable, with named non-blocking issues.
- `NO-GO` — something mandatory failed or could not be executed; never report it as finished.
<!-- AI-GOVERNANCE:END global-agent-policy -->

