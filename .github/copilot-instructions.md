# Sistema Solares — Agent Entry Point

<!-- AI-GOVERNANCE:BEGIN global-agent-policy v1 -->
<!-- GENERATED FROM AI-GOVERNANCE - DO NOT EDIT THIS SECTION MANUALLY.
     Source: C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md
     Regenerate: Sync-AgentPolicy.ps1 -Project SistemaSolares -Mode Apply -->

Project policy: `AGENTS.md` in this repository. Company-wide policy: `C:\Users\pc\DEV\AI-GOVERNANCE\GLOBAL_AGENT_POLICY.md`.

- Read `AGENTS.md` before substantial work. Audit before editing; report with evidence; never invent facts, endpoints, commands, or results.
- Multiple agents allowed; **one writer per worktree**. A writing agent needs its own worktree and its own `agent/<task>` branch.
- Pre-flight before writing: `git rev-parse --show-toplevel`, `git branch --show-current`, `git status --short`, `git worktree list`. Suspicious state → **stop**, change nothing, report `CONCURRENT WRITER RISK`.
- Minimal change, root cause, requested scope only. No unrelated refactors, no debug leftovers, no temporary TODOs.
- Never print, log, commit, or paste secrets, tokens, credentials, private keys, or `.env` values.
- Production is **read-only** by default: no deploy, migration, seed, or data write without explicit authorization in the current task.
- Compilation is not completion: run the project's real analysis/build/test commands, functional validation, and visual validation when UI changed.
- End every task with `GO`, `GO WITH ISSUES`, or `NO-GO`. A failed or unexecuted mandatory check means `NO-GO`.
<!-- AI-GOVERNANCE:END global-agent-policy -->

---

## Project notes

<!-- Project-specific additions go here, BELOW the generated block. Keep it short. -->

- Repository root: `C:\Users\pc\DEV\PROYECTOS\CLIENTES\SISTEMA_SOLARES`
- Default branch: `main`
- Canonical documents and commands: see `AGENTS.md` in the repository root.
