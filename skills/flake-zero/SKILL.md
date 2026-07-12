---
name: flake-zero
description: >-
  Autonomous mission: eliminate every flaky test until the suite passes N consecutive
  full green runs. Detect flakes by repeat-running the suite and mining CI retry
  history, diagnose each to root cause with a reproduction that raises the failure rate
  (never theorize), fix and ratchet (red-by-revert), then re-run the whole suite
  repeatedly to prove stability. Use when "kill the flaky tests", flaky suite, flake
  zero, deflake the CI, or an unattended test-stabilization run.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; a runnable
  test suite. Worker playbooks: mattpocock/skills diagnosing-bugs (feedback-loop-first)
  or addyosmani/agent-skills debugging-and-error-recovery — one router per worker.
  In-pack: merge-train, gate-steward, fleet-doctor, run-blackbox.
---

# Flake-Zero — the suite is green N times in a row, not just once

You are the **COORDINATOR** of an autonomous mission. The end state is STABILITY PROVEN
BY REPETITION: the full suite passes `{{GREEN_STREAK}}` consecutive runs (default 10)
with zero flakes, OR every remaining flake is quarantined with a tracked root-cause
ticket a human approved. A single green run proves nothing about a flake.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | detect→diagnose→fix→prove loop, evidence rules | this repo |
| **Worker playbooks** | feedback-loop-first debugging | Matt diagnosing-bugs OR Addy debugging |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · the suite runs to completion at least once (a suite that can't run is a
different mission — fix that first) · clean baseline.

## Mission parameters

- `{{BASE}}` · `{{MAX_WORKERS}}` · `{{TEST_CMD}}` (full-suite command) ·
  `{{DETECT_RUNS}}` (repeat count for flake detection, default 20) ·
  `{{GREEN_STREAK}}` (consecutive clean runs to declare done, default 10) ·
  `{{QUARANTINE}}` allowed? (skip-with-ticket vs must-fix).

## Phase graph

```
ORIENT → DETECT (repeat-run + CI history) → rank by flake rate
  → DIAGNOSE wave (raise the failure rate, find root cause) → FIX (ratchet red-by-revert)
  → build-blind REVIEW → merge-train → PROVE (streak runs) → loop until streak → REFLECT
```

## Phase 1 — DETECT (build the denominator of flakiness)

- Run `{{TEST_CMD}}` `{{DETECT_RUNS}}` times (parallel `PROFILE=ro` workers on isolated
  worktrees, different seeds/orders where the runner allows). Record per-test:
  pass/fail counts → **flake rate**. A test that fails k/{{DETECT_RUNS}} is a flake at
  rate k/N; deterministic failures (N/N) are BUGS, not flakes — route those to
  `backlog-zero`, out of this mission's scope.
- Mine CI retry history (`gh run list` / annotations) for tests that pass-on-retry —
  those flake in environments your local runs don't reproduce; capture them even at
  rate 0 locally.
- Ledger (`docs/flake-zero-progress.md`): `| test | flake-rate | CI-retries | ROOT-CAUSE
  | FIXED | PR | MERGED | STREAK-CLEAN |`. Rank by rate × blast-radius.

## Phase 2 — DIAGNOSE wave (feedback loop FIRST, never a theory)

One worker per flaky test, playbook = feedback-loop-first debugging:

- Build a loop that RAISES the failure rate — the mission's version of the
  diagnosing-bugs rule "goal is a higher reproduction rate, not clean repro": run the
  test in a tight loop, under load, with clock skew, with shuffled order, with the
  parallel siblings that share its state. Paste the command + a run showing elevated
  failure rate BEFORE proposing a cause. No red-capable loop → no root cause → say so.
- Classify the root cause (the flake taxonomy): order-dependence / shared mutable state
  / real time or timezone / network or external service / randomness or unseeded faker /
  resource leak or timeout-too-tight / async race. The class dictates the fix.

## Phase 3 — FIX + RATCHET

Per diagnosed flake (same-file fixes = merge chain):

1. Worktree (`--base-branch {{BASE}}`), `PROFILE=rw` worker.
2. Fix the ROOT CAUSE, not the symptom: inject the clock, seed the RNG, isolate the
   state, widen a genuinely-too-tight timeout (subprocess/scan-in-a-loop tests
   especially), fix the order-dependence — never `retry(3)` a flake into hiding
   (quarantine is explicit and tracked; a silent retry wrapper is banned).
3. **Ratchet (red-by-revert):** prove the fix — revert only the production/test change
   and show the flake returns at its measured rate; restore and show it's gone across a
   local mini-streak. This is the flake analogue of the failing-first test.
4. PR to `{{BASE}}`, build-blind REVIEW, `merge_ready` → **merge-train**.

## Phase 4 — PROVE (the streak is the definition of done)

After each wave merges, run the FULL suite `{{GREEN_STREAK}}` consecutive times (fresh
worktrees, varied seed/order). ANY flake resets the streak to zero and re-enters
detection with the new data. The mission converges only on an UNBROKEN streak. A flake
that survives `{{DETECT_RUNS}}`-run diagnosis with no root cause → quarantine
(skip-with-ticket) under a human gate, never a hidden retry.

## Completion contract (evidence)

- Every flake detected at Phase 1: root-caused + fixed + merged (with a red-by-revert
  ratchet recorded), or quarantined with a human-approved tracking ticket.
- The `{{GREEN_STREAK}}`-run clean streak pasted in the ledger (timestamps + seeds/orders
  per run — a streak you can't reproduce didn't happen).
- CI-only flakes: either reproduced-and-fixed, or the CI-environment cause documented.
- Zero `retry`/rerun wrappers added as "fixes" (grep the diff — their presence fails the
  mission).
- Promotion to default is out of scope.

## RESUME

`run-blackbox` RESUME scoped to this ledger; the streak counter lives in the ledger and
is re-verified by re-running, never trusted from memory — a claimed streak with no
pasted runs restarts at zero.

## Anti-patterns

- Theorizing a cause before a loop that reproduces at elevated rate (diagnosing-bugs
  Phase 1 gate).
- `retry(n)` / `--rerun-failures` as the fix (hides flakes, poisons the suite's signal).
- Declaring done on one green run (the whole point is repetition).
- Treating an N/N deterministic failure as a flake (it's a bug — wrong mission).
- Widening a timeout that masks a real race (fix the race; only widen genuinely-tight
  budgets).

## Handoff contract

Emits the flake ledger (rates, root causes, ratchets, streak runs), deterministic
failures handed to `backlog-zero`, and REFLECT learnings to `fleet-memory`. Schedulable
via `standing-fleet` (nightly detection run; wake the mission when new flakes appear).

## Related

`diagnose-swarm` (single hard-bug sibling), `backlog-zero` (deterministic failures go
there), `merge-train`, `fleet-doctor`, `gate-steward`, `run-blackbox`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the flake-rate/streak ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
