---
name: fleet-memory
description: >-
  Compounding cross-run memory for Orca fleets: append-only per-repo learnings JSONL
  written at REFLECT phases, injected into future dispatch preambles as "Prior learning
  applied", plus reviewer hit-rate stats that gate off specialists with zero findings
  across ten dispatches (security-lite/authz/sql never gated). Use when fleets keep re-hitting the same
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

`docs/fleet-memory/learnings.jsonl` — one JSON object per line (repo ships empty JSONL
files; append on first write, commit the store with the run):

```json
{"key": "worktree-selector-composite-id", "insight": "terminal create --worktree id:<uuid>
 fails; pass path:/abs/path", "evidence": "run 2026-07-12 task S3, 40 min lost",
 "confidence": 8, "fleet": "clean-sweep", "tags": ["worktrees"], "date": "2026-07-12",
 "status": "active"}
```

Field rules:
- `confidence`: integer **1–10**. Lines with confidence **< 5** do not inject; they wait
  for corroborating evidence (raise confidence on a later append, or supersede).
- `fleet`: owning fleet slug (exact match for inject).
- `tags`: optional string array for cross-cutting surfaces (`worktrees`, `merges`,
  `migrations`, …). Empty/omitted = fleet-only matching.
- `status`: `active` | `superseded:<newer-key>` | `retired:<reason>`. Never edit lines;
  append the superseding line.

`docs/fleet-memory/specialist-stats.jsonl` holds ONE LINE PER REVIEW DISPATCH —
`{"specialist": "authz", "run": "<ledger-slug>", "date": "2026-07-12", "findings": 2}` —
so "last 10 dispatches" is deterministically the last 10 lines for that specialist, no
cumulative counters to unpick. **`specialist` MUST be a canonical id** from the table
below (never free-text).

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

- **Match (in order):** (1) `status=active` and `confidence >= 5`; (2) exact `fleet`
  match to the task's fleet; (3) **or** non-empty intersection between the learning's
  `tags` and the task's declared tags (task specs list tags explicitly — no fuzzy
  "touches surface" guesses). Cross-fleet inject is forbidden unless tag intersection
  is non-empty.
- **Cap + tiebreak:** CAP at 5 per task. When more than 5 qualify, sort by
  `confidence` desc → `date` desc → `key` asc; take the top 5. Record the chosen keys
  and this rule echo in the ledger so two runs of the same fleet are reproducible.
- Workers that apply one report it in worker_done ("prior learning applied: <key>") —
  that echo is how `retro`-style review sees compounding happen.

## Prune — memory rots

Monthly (or via `standing-fleet` on a schedule): for each active line, check the
evidence still stands — referenced files/commands exist, the runtime behavior still
reproduces where cheap to check. Stale → `retired:<reason>` line. Two actives
contradicting → force the supersede decision now, not at 2 a.m. mid-run.

## Specialist ids (canonical — shared with review fleets)

| specialist id | Owning fleet | Axis |
|---------------|--------------|------|
| `standards` | `review-matrix` | Standards |
| `spec` | `review-matrix` | Spec |
| `security-lite` | `review-matrix` | Security-lite |
| `test-adequacy` | `review-matrix` | Test-adequacy |
| `sql` | `review-prod-fleet` | SQL / data (incl. migration safety) |
| `authz` | `review-prod-fleet` | AuthZ |
| `llm-trust` | `review-prod-fleet` | LLM/tool trust |
| `side-effects` | `review-prod-fleet` | Conditional side effects |

Stats lines and ledger gating rows MUST use these ids verbatim.

## Adaptive review gating (stats, not vibes)

**Who executes this:** the COORDINATOR of a review fleet (`review-matrix`,
`review-prod-fleet`) that has THIS skill loaded — it checks the stats before
`task-create`, drops a gated axis's task, and writes the ledger line. The review skills
name this as their optional pre-step; without fleet-memory loaded, nothing gates.

After each review fleet run, append the per-dispatch stats lines. Gating rule, checked
at fleet start:

- A specialist with **0 findings across its last 10+ dispatches** → gate OFF for this
  run (ledger line: `gated: <specialist>, 0/10+`), freeing its lane.
- **NEVER_GATE** (insurance axes, zero findings is the GOAL): `security-lite`, `authz`,
  `sql`. These run regardless — their value is the miss they'd catch.
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
- `confidence` is integer 1–10; lines with confidence < 5 don't inject.
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
