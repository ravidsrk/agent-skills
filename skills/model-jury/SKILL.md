---
name: model-jury
description: >-
  Multi-model Orca jury: same ticket implemented independently on different
  agents (e.g. codex vs claude) in isolated worktrees, dual-axis reviewed, then
  human gate to pick or merge. Use for high-stakes designs, "model jury", or
  comparing agent approaches. Expensive — use sparingly.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI) with multiple agent CLIs (codex, claude, …).
  Matt implement, tdd, code-review.
---

# Model-Jury

One ticket, **N independent implementations**, human picks.



## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — not on other skills in this pack, and not on in-process subagents.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca (`orca orchestration …`) |
| **Grammar** | CLI + lifecycle rules | **`orchestration` skill from the Orca CLI** (not this repo) |
| **This skill** | *what / when / why* on top of that grammar | this repo |
| **Workers** | AFK playbooks (Matt `/implement`, `/tdd`, …) | mattpocock/skills or this pack |

**Preflight (stop if any fail):** `orca status --json` running · orchestration experimental on · `orchestration` skill loaded · never substitute Task/subagent tools for `task-create` + `dispatch`.

**Full handoff** ("give this to another agent") → `orca-cli`, not supervised `dispatch --inject`, unless the user asked to supervise / wait for `worker_done`.

## We have Orca — we do not replace it

This skill **uses** the Orca multi-agent runtime and the `orchestration` skill. It is a strategy layer on top of Orca, not a substitute harness. Never reimplement task/dispatch/worker_done with in-process subagents.

## Protocol home

This skill is the JURY special case of `quorum` (Mode 2): independent candidates in
isolated worktrees, then a VOTE round where jurors never judge their own candidate.
Run the mechanics below through quorum's ballot/reduction/routing discipline — the
consensus table and denominator rules live there.

## Process

1. Freeze ticket + acceptance criteria (no scope drift mid-jury).
2. For each model/agent `M`:
   - `worktree create --name jury-<ticket>-<M> --no-parent --base-branch <BASE>` (pin the Git base — `--no-parent` only affects Orca lineage; without `--base-branch` a juror forks from the default branch and the comparison is invalid)
   - implement+tdd worker with **no access** to other jury worktrees
3. For each implementation: `review-matrix` axes (or dual code-review).
4. Coordinator comparison table: correctness, simplicity, test quality, standards.
5. `gate-create`: pick A / B / hybrid (human specifies merge rules).
6. Integrate winner onto BASE; archive losers (keep branches for audit).

## Rules

- No worker may read another jury branch.
- Same acceptance criteria for all.
- Cost warning up front (N× implement + N× review).

## Related

- `design-it-thrice` — design only, not full implement
- `matt-ship` — single-model default path

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

## Pick / hybrid rules

See `references/merge-rules.md` — default to pick, hybrid only on explicit human rule.
