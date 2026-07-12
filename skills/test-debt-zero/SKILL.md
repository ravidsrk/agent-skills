---
name: test-debt-zero
description: >-
  Autonomous mission: give every critical path a red-capable test. Map the untested
  critical surface (coverage + call-graph of the money paths), write failing-first tests
  en masse that assert real behavior, fix the bugs those tests surface PR-per-fix, and
  loop until every critical path has a test that fails when its production code is
  reverted. Use when "close the test gap", test debt zero, cover the critical paths,
  characterization tests, or an unattended test-hardening run. Not raw coverage-percent
  chasing — behavior coverage of the paths that matter.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; a runnable
  suite + coverage tool. Worker playbooks: addyosmani/agent-skills (TDD, testing-patterns)
  or mattpocock/skills (tdd) — one router per worker (verify skill names against the
  installed pack). In-pack: merge-train, fleet-doctor, gate-steward, run-blackbox.
---

# Test-Debt-Zero — every critical path has a test that fails when the code is reverted

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE:
every path on the agreed critical surface has at least one test that goes RED when its
production code is reverted (a mutation/revert-audited assertion — not a test that passes
against a broken implementation). Coverage percent is a proxy; the revert-check is the
truth.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | map→write→prove loop, evidence rules | this repo |
| **Worker playbooks** | TDD, characterization tests | Addy TDD OR Matt tdd (one router per worker) |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · suite + coverage run to completion at baseline · clean baseline.

## Mission parameters

- `{{BASE}}` · `{{MAX_WORKERS}}` · `{{TEST_CMD}}` + `{{COVERAGE_CMD}}` ·
  `{{CRITICAL_SURFACE}}` (the money/auth/data paths — confirmed with a human once; a
  test-debt mission that "covers everything" never converges) · `{{COVERAGE_FLOOR}}`
  (secondary target for non-critical code, optional).

## Phase graph

```
ORIENT → MAP critical surface (coverage gaps × call-graph) → human scope confirm
  → CHARACTERIZE waves (failing-first tests, PR-per-area) → SURFACED-BUG sub-loop
  → build-blind REVIEW → merge-train → PROVE (revert-audit each new test) → loop → REFLECT
```

## Phase 1 — MAP (define a finite critical surface)

- Run `{{COVERAGE_CMD}}`; intersect uncovered lines/branches with the call-graph of the
  critical entry points (money, auth, data-mutation, external contracts). Uncovered
  trivial getters are NOT the mission; uncovered branches on a payment path ARE.
- Ledger (`docs/test-debt-zero-progress.md`): `| path | why-critical | has-red-capable-
  test | TEST-PR | MERGED | REVERT-AUDITED | surfaced-bugs |`, one row per critical path.
- **Human scope confirm (gate #1):** the critical-surface list, one decision. This bounds
  the mission — without it, "every path" is unbounded.

## Phase 2 — CHARACTERIZE waves (failing-first, real assertions)

One `PROFILE=rw` worker per path-cluster (same-file tests = merge chain):

- Write the test to assert REAL expected behavior, then confirm it currently fails or
  the code has a gap — a test written to pass against current (possibly-wrong) behavior
  is a characterization LIE. Two outcomes:
  - code is correct, just untested → the test passes once written; **prove it earns its
    keep by reverting the covered production line and showing the test goes RED** (this
    is the mission's core evidence — a green test over reverted code is worthless).
  - the test reveals a BUG (behavior ≠ intent) → route to the SURFACED-BUG sub-loop.
- Follow the test pyramid (small/fast first), DAMP over DRY, assert state not
  interactions, prefer real > fake > stub > mock — the Addy/Matt testing discipline.
  Never weaken an assertion to make a red test green; that inverts the mission.

## Phase 3 — SURFACED-BUG sub-loop

A test that fails because the code is WRONG (not just untested) is a real bug:

- Log it as a finding; the fix is a separate concern from the coverage test. Small,
  clearly-correct fix → fix in the same PR with the now-passing test. Ambiguous or
  behavior-changing (is the old behavior load-bearing? Hyrum's Law) → PARK as a
  `needs-human` decision (the "fix" might break a caller relying on the quirk), or hand
  to `backlog-zero`. Never silently "fix" by asserting the buggy behavior as correct.

## Phase 4 — PROVE + loop

After each wave merges, RE-MAP coverage. New critical paths (from new code merged during
the run, or newly-reachable branches) enter the table. A path is DONE only when its test
is merged AND revert-audited RED. Loop until every row on the confirmed surface is
revert-audited. New surface discovered → new rows → next wave.

## Completion contract (evidence)

- Every critical-surface path: a merged test that goes RED on revert of its covered code
  (revert-audit recorded; spot-audited on a sample by a fresh worker).
- Every surfaced bug: fixed-with-test, or PARKED as needs-human with a reason, or handed
  to `backlog-zero` (referenced).
- No assertion weakened to pass (diff-audit: a test file whose assertions got looser is a
  red flag a fresh reviewer checks).
- Coverage before/after on the critical surface pasted in the ledger — but the pass
  criterion is the revert-audit set, not the percent.
- Promotion to default is out of scope.

## RESUME

`run-blackbox` RESUME scoped to this ledger; a test claimed merged is re-verified by
ancestry, and its revert-audit RED status is re-checkable by re-running — never trusted
from memory.

## Anti-patterns

- Chasing coverage percent instead of critical-path revert-audits (100% coverage with
  tautological asserts proves nothing).
- Writing tests that pass against current behavior without the revert-check (a green test
  over broken code is worse than no test — it certifies the bug).
- Silently asserting a surfaced bug's wrong behavior as correct (locks in the bug).
- Unbounded surface ("test everything") — the mission needs the confirmed critical list.

## Handoff contract

Emits the coverage ledger (paths, revert-audits, surfaced bugs), bugs handed to
`backlog-zero`, and REFLECT learnings to `fleet-memory`. Schedulable via `standing-fleet`
(re-map after each merge to default; wake when critical coverage regresses).

## Related

`flake-zero` (test stability sibling), `backlog-zero` (surfaced bugs go there),
`feature-factory` (builds tests into new features), `merge-train`, `fleet-doctor`,
`gate-steward`, `run-blackbox`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the critical-path/revert-audit ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
