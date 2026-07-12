---
name: spec-issue-fleet
description: >-
  Orchestrate gstack /spec into a GitHub issue then Orca worktree implement fleet. Use
  when spec issue fleet, gstack spec to build, or issue-linked autonomous implementation.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Spec-Issue-Fleet — gstack /spec → issue → Orca implement

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


## Process
```
SPEC worker (gstack /spec → precise spec + GH issue)
  → human freeze gate on issue
  → ticketize (to-tickets or issue checklist)
  → implement fleet (matt-ship implement phases)
  → review + PR; /ship may close source issue on merge
```

## Rules
- Spec freeze is human for product intent.
- Implementation is AFK on Orca.
- Prefer issue as source of truth for /ship close-on-merge.

## Requires
Orca + gstack (`/spec`) + Matt skills (`/to-tickets`, and `matt-ship` phases for the implement fleet). The Gstack-only install track is NOT sufficient — install README Track C too.

## Related
`autoplan-fleet`, `matt-ship`, `gstack-ship-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

