---
name: cso-fleet
description: >-
  Orchestrate gstack /cso security audit under Orca, then optional PR-per-finding fixes.
  Use when cso fleet, autonomous security audit, OWASP pass, or threat model plus fix. Not
  a substitute for clean-sweep on an existing audit doc.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# CSO-Fleet — OWASP/STRIDE audit → fix on Orca

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | *what / when / why* | this repo |
| **Worker methodology** | gstack / Matt playbooks injected into workers | garrytan/gstack, mattpocock/skills |

**Preflight:** `orca status --json` · orchestration experimental on · `orchestration` skill loaded · never substitute in-process Task/subagents for `task-create` + `dispatch`.

**Full handoff** → `orca-cli` unless user asked to supervise / wait for `worker_done`.


You are the **COORDINATOR**.

## Phase graph
```
CSO worker (gstack /cso → OWASP Top 10 + STRIDE report)
  → SKEPTIC triage findings (real vs noise)
  → FREEZE finding list
  → FIX waves (one PR per P0/P1 finding on BASE)
  → RE-CSO smoke worker
  → human gate: residual P2 backlog
```

## Rules
- CSO worker is read-only audit; builders are separate (build-blind).
- Same merge/preflight discipline as clean-sweep.
- Secrets: no live keys; decline user-pasted production secrets.
- Distinct from `adversarial-ticket` (per-ticket) and `clean-sweep` (given backlog).

## Related
`clean-sweep`, `adversarial-ticket`, `review-prod-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

