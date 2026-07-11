---
name: diagnose-swarm
description: >-
  Multi-role Orca swarm for hard bugs using Matt diagnosing-bugs: repro worker
  raises flake rate, optional bisect worker, fix+/tdd worker, dual-axis review.
  Use when "diagnose swarm", intermittent bugs, regressions between known-good
  states, or bugs that resist first-glance fixes. Coordinator holds the tight
  feedback-loop invariant — no theorising without a red command.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt diagnosing-bugs, tdd, code-review;
  optionally improve-codebase-architecture. git; test runner.
---

# Diagnose-Swarm

Hard bugs need a **tight red command** before any theory. Roles:

| Role | Skill / duty | Deps |
|------|----------------|------|
| **A Repro** | `/diagnosing-bugs` loop: raise reproduction rate; one command that goes red | — |
| **B Bisect** (opt) | Timeline / git bisect once red command exists | A |
| **C Fix** | `/tdd` regression first, then fix | A |
| **D Review** | Dual-axis `/code-review` | C |
| **E Seam** (opt) | `/improve-codebase-architecture` if “no good seam to lock the bug” | D or human |



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

## Invariants

1. **No fix worker until A delivers a red command** (path + args in `worker_done`).
2. Fix worker must add a **regression test that fails if the fix is reverted**.
3. Build-blind review (D ≠ C).
4. Flakes: raise rate; don’t “retry until green” and call it fixed.

## Process

1. Orient: pin last-good / first-bad if known; capture env.
2. Dispatch **A** in a worktree (or same tree if needs local state).
3. On A done: gate human if repro is environmental; else dispatch B (optional) + C.
4. C → D review matrix axes.
5. If architecture is the real finding: E or hand to `architecture-sprint`.

## Related

- Single-session path: Matt `/diagnosing-bugs` alone (no Orca)
- `review-matrix` for the D phase alone

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

## Repro gates

See `references/repro-gates.md`. No fix without a red command.
