---
name: research-then-grill
description: >-
  Parallel evidence gathering before HITL grilling: Orca workers run Matt
  /research and/or monid deep-research, join a cited research pack, then
  coordinator runs grill-with-docs that must ground questions in the pack.
  Use when "research then grill", pre-flight evidence before design, or
  avoiding vibe-based planning. Research is input — never a substitute for
  grilling or a drafted product decision.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt research and/or agent-skills deep-research
  (monid). grill-with-docs for the HITL phase. MONID_API_KEY if monid path used.
---

# Research-Then-Grill

**Evidence first, interview second.**



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

## Process

### 1. Frame the decision

One sentence: what decision will this research inform?

### 2. Parallel research workers

| Worker | Tool | Output |
|--------|------|--------|
| Primary sources | Matt `/research` | `research/<slug>.md` cited |
| Discourse pack | monid `deep-research` | `research/<slug>/research-*.{md,json}` |

Dispatch 1–N workers with non-overlapping source mandates. `worker_done` requires `reportPath`.

### 3. Join pack (coordinator)

Write `research/<slug>/PACK.md`:

- Decision question
- Convergences across sources
- Contradictions
- Gaps
- Links to raw dumps (**no editorial “bottom line” product decision**)

### 4. Grill (HITL, coordinator)

Run `/grill-with-docs`. Rules for this phase:

- Every major question should **reference PACK.md** (or admit gap).
- Do not invent market facts that research didn’t support.
- Update CONTEXT.md/ADRs as usual.

### 5. Exit

Hand to `wayfinder-fleet` (if still foggy) or `matt-ship` / `/to-spec`.

## Anti-patterns

- Research worker that writes the product plan
- Grilling that ignores the pack
- Single-source research called “deep”

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

