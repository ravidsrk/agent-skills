---
name: test-debt-zero
description: >-
  Autonomous mission: give every critical path a mutation-audited test. Map the untested
  critical surface (coverage + call-graph of the money paths), write characterization
  tests that assert real behavior, fix the bugs those tests surface PR-per-fix, and loop
  until every critical path has a test that fails at its assertion under a
  semantics-preserving mutation of its code. Use when "close the test gap", test debt zero, cover the critical paths,
  characterization tests, or an unattended test-hardening run. Not raw coverage-percent
  chasing — behavior coverage of the paths that matter.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; a runnable
  suite + coverage tool. Worker playbooks: addyosmani/agent-skills (TDD, testing-patterns)
  or mattpocock/skills (tdd) — one router per worker (verify skill names against the
  installed pack). In-pack: merge-train, fleet-doctor, gate-steward, run-blackbox.
---

# Test-Debt-Zero — every critical path has a test that dies under mutation

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE:
every path on the agreed critical surface has at least one test that FAILS AT ITS
ASSERTION under a semantics-preserving mutation of its production code, with the harness
still runnable (a compile/import break is NOT proof — it shows source-shape dependence,
not behavior coverage). Coverage percent is a proxy; the mutation-audit is the truth.

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
  → CHARACTERIZE waves (mutation-audited tests, PR-per-area) → SURFACED-BUG sub-loop
  → build-blind REVIEW → merge-train → PROVE (mutation-audit each new test) → loop → REFLECT
```

## Phase 1 — MAP (define a finite critical surface)

- Run `{{COVERAGE_CMD}}`; intersect uncovered lines/branches with the call-graph of the
  critical entry points (money, auth, data-mutation, external contracts). Uncovered
  trivial getters are NOT the mission; uncovered branches on a payment path ARE.
- Ledger (`docs/test-debt-zero-progress.md`): `| path | why-critical | has-mutation-
  audited-test | TEST-PR | MERGED | MUTATION-AUDITED | outcome | surfaced-bugs |`.
- **Human scope confirm (gate #1):** the critical-surface list, one decision. This bounds
  the mission — without it, "every path" is unbounded.

## Phase 2 — CHARACTERIZE waves (mutation-audited, real assertions)

One `PROFILE=rw` worker per path-cluster (same-file tests = merge chain):

- Write the test to assert REAL expected behavior, then confirm it currently fails or
  the code has a gap — a test written to pass against current (possibly-wrong) behavior
  is a characterization LIE. Two outcomes:
  - code is correct, just untested → the test passes once written; **prove it earns its
    keep with a semantics-preserving MUTATION** (flip a boundary, negate a condition,
    zero a returned value — a change that keeps the code COMPILING and the harness
    RUNNABLE) and show THIS test fails at its behavioral assertion. A revert that breaks
    compilation/imports/fixtures proves dependence on source SHAPE, not on behavior —
    that does not count. The mutation must fail the targeted assertion while the suite
    otherwise runs.
  - the test reveals a BUG (behavior ≠ intent) → route to the SURFACED-BUG sub-loop
    (only here is it a genuine failing-first/RED test in the TDD sense).
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
is merged AND mutation-audited (fails at its assertion under mutation, harness runnable).
Loop until every row on the confirmed surface is mutation-audited. New surface → new rows.

## Two named terminal outcomes

- **COVERED** — every path on the confirmed critical surface has a merged, mutation-audited
  test, and every surfaced bug is fixed-with-test. A completed mission.
- **COVERED-WITH-PARKED** (degraded, not COVERED) — all writable paths mutation-audited, but
  ≥1 surfaced bug is PARKED as needs-human (load-bearing quirk / behavior-change decision)
  or a path can't be tested without a human decision. The ledger names each parked item.
  Legitimate stop, never reported as COVERED.

## Completion contract (evidence — the outcome must be named)

- Ledger outcome line = `COVERED` or `COVERED-WITH-PARKED` with the parked list.
- Every critical-surface path: a merged test that fails at its assertion under a
  semantics-preserving mutation of its covered code, harness still runnable
  (mutation-audit recorded; spot-audited on a sample by a fresh worker).
- Every surfaced bug: fixed-with-test, or PARKED as needs-human with a reason, or handed
  to `backlog-zero` (referenced).
- No assertion weakened to pass (diff-audit: a test file whose assertions got looser is a
  red flag a fresh reviewer checks).
- Coverage before/after on the critical surface pasted in the ledger — but the pass
  criterion is the mutation-audit set, not the percent.
- Promotion to default is out of scope.

## RESUME

`run-blackbox` RESUME scoped to this ledger; a test claimed merged is re-verified by
ancestry, and its mutation-audit status is re-checkable by re-running — never trusted
from memory.

## Anti-patterns

- Chasing coverage percent instead of critical-path mutation-audits (100% coverage with
  tautological asserts proves nothing).
- Writing tests that pass against current behavior without the mutation-check (a green
  test insensitive to the behavior is worse than no test — it certifies the status quo).
- Accepting a compile/import break as the mutation proof (proves source-shape dependence,
  not behavior — the mutation must keep the harness runnable and fail the assertion).
- Silently asserting a surfaced bug's wrong behavior as correct (locks in the bug).
- Unbounded surface ("test everything") — the mission needs the confirmed critical list.

## Handoff contract

Emits the coverage ledger (paths, mutation-audits, surfaced bugs), bugs handed to
`backlog-zero`, and REFLECT learnings to `fleet-memory`. Schedulable via `standing-fleet`
(re-map after each merge to default; wake when critical coverage regresses).

## Related

`flake-zero` (test stability sibling), `backlog-zero` (surfaced bugs go there),
`feature-factory` (builds tests into new features), `merge-train`, `fleet-doctor`,
`gate-steward`, `run-blackbox`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the critical-path/mutation-audit ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
