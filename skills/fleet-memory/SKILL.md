---
name: fleet-memory
description: >-
  Compounding cross-run memory for Orca fleets: append-only per-repo learnings JSONL
  written at REFLECT phases, injected into future dispatch preambles as "Prior learning
  applied", plus reviewer hit-rate stats that gate off specialists with zero findings
  across ten dispatches (security never gated). Use when fleets keep re-hitting the same
  gotchas, "make run N+1 smarter than run N", fleet learnings, prune stale learnings,
  or adaptive review gating. Pattern adapted from gstack's learnings/retro loop.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). python3. A repo the
  fleet runs in (the store lives at docs/fleet-memory/).
---

# Fleet-Memory — run N+1 must be smarter than run N

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | dispatch preambles the learnings ride in; provenance the stats read | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the store, the write/inject/prune discipline, the gating stats | this repo |

Attribution: the compounding loop (auto-captured learnings, visible re-application,
prune-on-contradiction, hit-rate-gated specialists with NEVER_GATE insurance) is
gstack's learnings/retro/specialist-stats design, adapted to Orca fleets.

## The store (append-only, latest-per-key wins)

`docs/fleet-memory/learnings.jsonl` — one JSON object per line:

```json
{"key": "worktree-selector-composite-id", "insight": "terminal create --worktree id:<uuid>
 fails; pass path:/abs/path", "evidence": "run 2026-07-12 task S3, 40 min lost",
 "confidence": 8, "fleet": "clean-sweep", "date": "2026-07-12", "status": "active"}
```

`status`: `active` | `superseded:<newer-key>` | `retired:<reason>`. Never edit lines;
append the superseding line. `docs/fleet-memory/specialist-stats.jsonl` holds one line
per review dispatch: `{"specialist": "...", "dispatches": n, "findings": n, "date": ...}`.

## Write — at REFLECT, not in the heat

At every fleet's REFLECT/wind-down phase (and doctor BREAKs, blackbox AUDITs):

- Capture ONLY what would save ≥15 minutes on a future run (the gstack bar, raised for
  fleet cost). Ask: "would run N+1 hit this?" — no → don't write it.
- One insight per line, imperative, with the evidence pointer. No essays.
- Contradiction with an existing active line → append the new line AND a superseding
  status line for the old key. Both visible forever; only one active.

## Inject — visible, bounded, verbatim

At dispatch time the coordinator prepends to the TASK spec:

```
PRIOR LEARNINGS (fleet-memory, apply unless your task contradicts them):
- [worktree-selector-composite-id] terminal create --worktree id:<uuid> fails; pass path:/abs/path
- [...]
```

- Selection: active lines whose `key`/`fleet` match the task's fleet or touch its
  surface (worktrees, merges, migrations…). CAP at 5 per task — memory is seasoning,
  not a second spec.
- Workers that apply one report it in worker_done ("prior learning applied: <key>") —
  that echo is how `retro`-style review sees compounding happen.

## Prune — memory rots

Monthly (or via `standing-fleet` on a schedule): for each active line, check the
evidence still stands — referenced files/commands exist, the runtime behavior still
reproduces where cheap to check. Stale → `retired:<reason>` line. Two actives
contradicting → force the supersede decision now, not at 2 a.m. mid-run.

## Adaptive review gating (stats, not vibes)

After each review fleet run, append specialist stats. Gating rule, checked at fleet
start:

- A specialist with **0 findings across its last 10+ dispatches** → gate OFF for this
  run (ledger line: `gated: <specialist>, 0/10+`), freeing its lane.
- **NEVER_GATE list** (insurance axes, zero findings is the GOAL): security/authz,
  data-migration. These run regardless — their value is the miss they'd catch.
- Any gated specialist re-enters after one exploratory dispatch per 10 runs (drift
  check) or when its surface changes (new dependency class, new data layer).

## Completion contract

A fleet integrating this skill is DONE with memory when: REFLECT wrote its lines (or an
explicit "nothing ≥15 min" note), injected keys are listed per dispatched task in the
ledger, worker echoes are recorded, and stats lines exist for every review dispatch.
Memory with no ledger trace is superstition.

## Rules

- Learnings state FACTS about this repo/runtime, never policy (policy lives in skills;
  a learning that contradicts a skill is a PR to the skill, not a memory line).
- The injection cap (5) is hard — over-remembering is under-thinking.
- Confidence <5 lines don't inject; they wait for corroborating evidence.
- Secrets never enter the store (it's committed); evidence pointers, not payloads.

## Handoff contract

Consumes: `run-blackbox` AUDIT patterns, doctor logs, REFLECT notes. Emits: the two
JSONL stores + per-run ledger lines (injected keys, echoes, gated specialists).
`review-matrix` / `review-prod-fleet` read the gating decision at start; `retro-cron`
reports the compounding ("applied N learnings, wrote M, retired K").

## Related

`retro-cron`, `run-blackbox`, `review-matrix`, `review-prod-fleet`, `standing-fleet`
(scheduled prune), gstack `/learn` + `/retro` (upstream pattern).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the memory lines extend

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
