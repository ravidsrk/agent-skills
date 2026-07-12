---
name: gate-steward
description: >-
  Governed decision gates for Orca fleets: classify every gate mechanical / taste /
  one-way, auto-resolve mechanical with an audit trail, batch taste into one
  decision-ready brief, NEVER auto-resolve one-way doors, and park (never default)
  timed-out asks. Use when a fleet drowns the human in gates, "auto-decide the
  mechanical stuff", decision gate policy, gate triage, or unattended runs that park
  questions between sessions. Runs in the coordinator.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). The supervised
  fleet's dependencies. A gates registry file per repo (created on first run).
---

# Gate-Steward — who answers what, and never the wrong who

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | `ask`/`reply` (worker gates), `gate-create`/`gate-resolve` (DAG gates), timeout behavior | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the classification + resolution policy on top | this repo |

## The two gate kinds (do not conflate — the runtime doesn't)

- **Worker gates:** a worker's blocking `ask` → `decision_gate` MESSAGE. Times out
  (default ~10 min), then RE-ASKS under a NEW id. Answered with `reply --id <CURRENT>`.
- **DAG gates:** coordinator-created `gate-create --task <id>` ROWS that block a task
  until `gate-resolve`. Nothing times them out — they block until resolved, and the
  resolution is injected into the task's next dispatch preamble.

## Classification (every gate, before any answer)

| Class | Test | Resolver |
|-------|------|----------|
| **Mechanical** | one defensible answer exists (tooling choice with a repo precedent, naming, retry-or-not on a transient error, ordering with no interaction) | steward auto-resolves, audited |
| **Taste** | reasonable people disagree; reversible (API shape, copy, structure within spec) | steward picks the recommendation, BATCHES for the human — work continues, human can veto |
| **One-way** | hard/impossible to reverse or out-of-authority: merges to default, deploys, rollbacks, deletions, spend, scope changes, anything guard-policy or a fleet names a human gate | HUMAN ONLY — never auto-resolved, never defaulted on timeout |

When unsure between classes, escalate one level. The registry (`docs/gates-registry.md`)
records reusable classifications: `<pattern> · class · rationale`; one-way entries can
never be downgraded by the steward — only the human edits those lines.

## Resolution flows

**Mechanical (worker gate):**
```
orca orchestration reply --id <CURRENT re-ask id> \
  --body "DECISION = <answer> — proceed now, do not ask again. [steward:mechanical]"
```
+ one audit line in the ledger: `gate <id> · mechanical · <answer> · <one-line why>`.
Same decision for a DAG gate: `gate-resolve --id <gate> --resolution "<answer> [steward:mechanical]"`.

**Taste:** resolve NOW with the recommended option (work continues), tag
`[steward:taste-pending-veto]`, and add to the batch brief. The brief is decision-ready
(Matt "push right"): per item — one-line question · what the steward chose · why · cost
if wrong · link (reportPath / diff), never raw transcripts. Deliver ONE brief per
checkpoint (fleet JOIN phase, or run end), not a ping per gate. A human veto becomes a
fix task; vetoed patterns get a registry entry upgrading them.

**One-way:** raise to the human immediately:
```
orca orchestration ask --to <human-facing terminal> --question "<the decision>" \
  --options "A,B" --timeout-ms 570000
```
No human within the window → **PARK, never default**: record
`PARKED gate <id> · one-way · waiting-human` in the ledger, `gate-create` on the blocked
task so the DAG holds it, and let the run continue elsewhere or end. `standing-fleet`
runs re-raise parked gates from the ledger at the next trigger.

## Timeout handling (worker asks)

A timed-out `ask` re-asks under a new id — always answer the LATEST (heartbeats name the
blocking gate id). For one-way questions a worker keeps re-asking about: reply
"PARKED for human — stop asking; `worker_done` blocked with the question in your report"
so the worker releases the terminal instead of looping.

## Completion contract

Every gate raised during the run appears in the ledger exactly once with: class, resolver
(`steward:mechanical` / `steward:taste-pending-veto` / `human` / `PARKED`), the answer,
and the audit line. Batched taste brief delivered at the declared checkpoint. Zero
one-way gates answered by anything but a human. An unaccounted gate means NOT done.

## Rules

- The steward never answers its own escalations (no self-dealing: a question the steward
  raised to the human is human-only).
- Classification happens BEFORE reading the recommended option — the option's
  attractiveness is not evidence of mechanicalness.
- Registry upgrades only ratchet toward more-human (mechanical→taste→one-way); downgrades
  require the human editing the registry.
- Guard-policy active ⇒ its human-gate list is one-way here, verbatim.

## Handoff contract

Ledger gate lines + `docs/gates-registry.md` are the artifacts. `autoplan-fleet`
delegates its AUTO_DECIDE layer-2 to this skill; `standing-fleet` re-raises PARKED lines;
`merge-train` treats every merge-to-default as one-way through this skill.

## Related

`autoplan-fleet`, `standing-fleet`, `guard-policy`, `merge-train`, `headless-mode`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the gate lines extend

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
