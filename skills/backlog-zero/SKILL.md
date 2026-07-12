---
name: backlog-zero
description: >-
  Autonomous mission: drain the ENTIRE issue tracker to zero unhandled issues. Every
  open issue gets triage-verified (reproduced or refuted with evidence), every real one
  gets a fix PR on an integration branch with a failing-first test, build-blind review,
  a verified merge, and an evidence-linked close; the rest park with rationale. Use when
  "drain the backlog", "close every issue", backlog zero, tracker cleanup mission, or an
  unattended issue-fixing run. Peer of clean-sweep (audit findings) — this one is
  tracker-driven and loops until the tracker is dry.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh (or Linear
  via orca linear). Worker playbooks: mattpocock/skills (triage, tdd, code-review) OR
  addyosmani/agent-skills (debugging, TDD, build contract) — one pack per worker, never
  two routers. In-pack machinery: merge-train, fleet-doctor, gate-steward, run-blackbox.
---

# Backlog-Zero — the tracker is empty or every survivor has a reason

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE, not
effort: every issue that was open when the run started (and every one filed during it)
is CLOSED with a merged fix or a refutation, or PARKED with a written reason a human
approved. You do not implement or review; you dispatch, verify, and keep the ledger.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | phases, gates, evidence rules | this repo |
| **Worker playbooks** | triage / debug / tdd / review methods | Matt OR Addy per worker (never both routers) |

**Preflight:** `orca status --json` · orchestration experimental on · `orchestration`
skill loaded · `python3 scripts/preflight.py --base {{BASE}}` green (BASE ≠ default —
fixes NEVER land straight on production) · tracker readable (`gh issue list` or
`orca linear list`) · clean baseline in the coordinator worktree (`git status
--porcelain` empty — the clean-baseline rule from the Addy build flow: never absorb unrelated work).

## Mission parameters (confirm once, then run)

- `{{BASE}}` integration branch · `{{TRACKER}}` gh|linear · `{{MAX_WORKERS}}` (~3-5)
- `{{SCOPE}}` label filter or "all open" · `{{PARK_LABEL}}` (default `parked-needs-human`)
- Standing authorization to close REFUTED issues: per-batch human gate (default) or
  pre-granted for this run (recorded in the ledger — a one-way grant via gate-steward).

## Phase graph

```
ORIENT → ENUMERATE → TRIAGE-VERIFY wave (ro) → human batch gate (refutations)
  → FIX waves (PR-per-issue, failing-first test) → build-blind REVIEW → merge-train
  → CLOSE with evidence → re-ENUMERATE (loop until dry) → REFLECT
```

## Phase 1 — ENUMERATE (the denominator)

Record the run-start timestamp `T0` in the ledger header FIRST. Then the denominator is
two queries, not one — listing only currently-open issues misses ones created and closed
between waves:

1. Every open issue in scope (`gh issue list --state open` / `orca linear list`),
   paginated to the end — a truncated listing is a silent mission failure.
2. Every issue CREATED or REOPENED since `T0`, any state
   (`gh issue list --state all --search "created:>=T0"` + a reopened-events sweep) — this
   catches issues that opened and were externally closed mid-run; each still needs a
   ledger row (CLASS = externally-resolved, with the closing reference) so the final
   count is honest.

Ledger table (`docs/backlog-zero-progress.md`), one row per issue:

```
| # | title | VERIFIED | CLASS | FIXED | PR | MERGED | CLOSED | evidence |
```

`CLASS` ∈ real-bug · real-feature-small · refuted · duplicate · externally-resolved ·
needs-human (design/scope/one-way) · out-of-scope. Re-run BOTH queries each loop — the
loop, not the first pass, is the mission.

## Phase 2 — TRIAGE-VERIFY wave (read-only workers)

One `PROFILE=ro` worker per issue (batch by `{{MAX_WORKERS}}`), playbook = Matt triage
discipline + the reproduce step of a debugging playbook (Addy's 5-step or Matt
diagnosing-bugs — pick ONE per worker TASK):

- A bug claim is VERIFIED only by a red-capable reproduction (command + failing output
  pasted in the report) — reading code and agreeing is not verification.
- Non-reproducible → work the decision tree (timing/env/state/random); still nothing →
  REFUTED with the attempts logged, or needs-human if the report implies private state.
- Duplicates: search by domain concept, not report wording; link the survivor.
- Workers NEVER mutate the tracker — evidence goes in `worker_done` reportPath; the
  coordinator writes the ledger.

**Human batch gate #1 (gate-steward one-way unless pre-granted):** closing REFUTED /
duplicate issues — a batch brief with per-issue evidence links, one decision.

## Phase 3 — FIX waves (the clean-sweep pipeline, issue-shaped)

Per real issue, in DAG order (issues touching the same hot files form merge chains):

1. Worktree per issue (`--base-branch {{BASE}}`), `PROFILE=rw` worker via
   `scripts/spawn_worker.sh`.
2. Worker TASK embeds an autonomous-build contract (the Addy build flow is the
   reference; verify exact skill/command names against the installed pack): clean
   baseline · **for a bug, a red-capable reproduction test FIRST** (the Phase-2 repro
   becomes the regression test); **for a `real-feature-small`, a failing acceptance
   test FIRST** (no prior failing behavior exists to reproduce) · smallest change ·
   commit-per-task, staged files only, author {{MAINTAINER}}, no trailers · anything
   irreversible (auth, destructive migration, payments, deletes, secrets) STOPS and
   escalates via `ask` — never improvised.
3. PR to `{{BASE}}` (integrator role, never the builder), body maps the issue's
   acceptance criteria.
4. Build-blind REVIEW: fresh terminal, Matt `/code-review` ONCE (both axes) or this
   pack's review-matrix rubrics — reviewed SHA recorded.
5. `merge_ready` to the **merge-train** conductor (reviewed-SHA freshness, ancestry-
   verified merge). Any conductor rebase voids review — the train handles it.
6. CLOSE the issue with the merge SHA + one completion comment linking PR and test.
   Fix-backed closes need no extra human gate — the evidence chain is the authorization.

Stalls and dead workers: **fleet-doctor** owns recovery (attempt budget, fresh
terminals, circuit-breaker escalation). Decisions: **gate-steward** (mechanical
auto-resolved + audited; taste batched; one-way human).

## Phase 4 — LOOP UNTIL DRY

Re-ENUMERATE after every wave. New issues → new rows → next wave. The mission converges
when a full enumeration finds ZERO issues that are not (a) closed with evidence, or
(b) `{{PARK_LABEL}}`-parked with a human-approved reason. One clean enumeration = dry.

## Completion contract (the mission's definition of done — evidence, never effort)

- Ledger row complete for EVERY issue that was ever open during the run.
- Every CLOSED-as-fixed issue: merged PR (ancestry-verified on `{{BASE}}`) + a test that
  failed before the fix (revert-check spot-audited on a 10% sample by a fresh worker).
- Every CLOSED-as-refuted issue: evidence link + the batch gate that approved it.
- Every PARKED issue: label + reason + the human decision reference.
- Final enumeration output pasted in the ledger showing the dry state.
- BASE→default promotion is OUT of mission scope — open the promotion PR, stop.

## RESUME

Coordinator died → `run-blackbox` RESUME (scope = this ledger's coordinator handle +
task ids), reconcile the issue table against tracker state + git (`gh issue view`,
ancestry checks) — the tracker and git outrank both ledger and provenance for CLOSED/
MERGED claims. Re-enter at the current phase; never re-close a closed issue.

## Anti-patterns (mission killers)

- Fixing without the Phase-2 repro (you'll "fix" symptoms and close real bugs unfixed).
- Closing anything from worker memory — closes happen only off verified merges/gates.
- One mega-PR for many issues (evidence chain breaks; merge-train exists — use it).
- Letting enumeration truncate (partial denominator = "done" that isn't).
- Two playbook routers in one worker TASK (conflicting TDD definitions — pick one pack
  per worker; see AGENTS.md one-router rule).

## Handoff contract

Emits: the ledger (issue table + gates + doctor log), per-issue reportPaths, review
findings in the AGENTS.md schema, and a REFLECT block of `fleet-memory` learnings.
Schedulable via `standing-fleet` (precheck: open-issue count > 0).

## Related

`clean-sweep` (audit-findings peer), `triage-to-fleet` (the supervised HITL sibling),
`ready-agent-drain` (single-label subset), `merge-train`, `fleet-doctor`,
`gate-steward`, `run-blackbox`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the issue-table ledger schema for this mission

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
