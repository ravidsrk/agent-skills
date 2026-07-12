---
name: perf-sweep
description: >-
  Autonomous mission: bring every critical user journey within its performance budget.
  Baseline each journey with real measurement (Core Web Vitals / server timings), fix
  budget breaches PR-per-hotspot with a before/after number, re-benchmark with a
  2-consecutive-confirmation to beat noise, and loop until every journey is within budget
  or the residual is parked with a reason. Use when "the app is slow", perf sweep,
  performance budget, Core Web Vitals, "get under budget", or an unattended
  performance-hardening run. Measure-first — never guess-and-optimize.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; a way to
  MEASURE (Lighthouse/DevTools MCP for web CWV, or a server/profiler harness). Worker
  playbooks: addyosmani/agent-skills (performance-optimization, web-performance-auditor,
  browser-testing-with-devtools) or gstack (benchmark, browse daemon) — one router per
  worker. In-pack: merge-train, fleet-doctor, gate-steward, run-blackbox, benchmark-fleet.
---

# Perf-Sweep — every journey within budget, proven by a before/after number

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE: every
critical journey meets its declared budget, proven by MEASURED before/after numbers that
hold across two consecutive runs (a single fast measurement is noise). Guessing at
optimizations without a measurement is banned — the metric is the mission.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | measure→fix→re-measure loop, evidence | this repo |
| **Worker playbooks** | perf profiling, CWV, benchmarks | Addy performance-optimization OR gstack benchmark |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · a working MEASUREMENT path (a fleet that can't measure can't run this mission —
fix that first) · clean baseline.

## Mission parameters

- `{{BASE}}` · `{{MAX_WORKERS}}` · `{{JOURNEYS}}` (the critical paths + their budgets —
  e.g. LCP≤2.5s / INP≤200ms / CLS≤0.1 for web, or p95≤Xms for an endpoint; confirm once) ·
  `{{MEASURE_CMD}}` (Lighthouse/DevTools/benchmark harness) · `{{ENV}}` (staging URL /
  local / prod-read-only — measurement must be REPRESENTATIVE, not a dev build).

## Phase graph

```
ORIENT → BASELINE every journey (measure ×2) → rank breaches by gap×traffic
  → DIAGNOSE hotspot (profile, find the actual bottleneck) → FIX (PR-per-hotspot, before/after)
  → build-blind REVIEW → merge-train → RE-BENCHMARK (2 consecutive) → loop → REFLECT
```

## Phase 1 — BASELINE (measure, don't assume)

- `PROFILE=ro` worker per journey runs `{{MEASURE_CMD}}` TWICE (perf numbers are noisy —
  one run is an anecdote). Record the metric + which budget it breaches and by how much.
  **Metric-honesty rule (the web-performance-auditor law): never fabricate a number.** A
  journey you couldn't measure is `unmeasured`, flagged for a human — not assumed-fine.
- Ledger (`docs/perf-sweep-progress.md`): `| journey | budget | baseline (×2) | breach |
  bottleneck | FIXED | before→after | PR | MERGED | CONFIRMED (×2) |`.
- Rank by gap × traffic/importance — the slowest low-traffic admin page is not the first
  fix.

## Phase 2 — DIAGNOSE the bottleneck (measure-first, per hotspot)

`PROFILE=ro` profiler worker per breaching journey:

- Profile to find the ACTUAL bottleneck (trace/flame-graph/waterfall), don't pattern-match
  to a favorite cause. The Addy symptom→cause decision tree: slow LCP vs slow INP vs
  bundle vs N+1 vs unbounded fetch vs render thrash each point at different fixes.
- Name the one bottleneck this journey's breach is dominated by; a fix PR targets it, not
  a scattershot of micro-opts.

## Phase 3 — FIX waves (PR-per-hotspot, before/after is mandatory)

`PROFILE=rw` worker per hotspot (same-file fixes = merge chain):

- Fix the named bottleneck (the Addy anti-pattern catalog: fix the N+1, split the bundle,
  bound the fetch, memoize the re-render, add the cache — whichever the profile pointed
  at). **The PR body MUST carry a measured before→after for the target journey** — a perf
  fix with no number is unverifiable and doesn't merge.
- Guard against regression: add/extend a perf budget in CI where the harness supports it
  (`bundlesize`, `lhci`) so the win can't silently rot.
- Correctness first: a fix that speeds the journey but changes behavior is a bug — the
  build-blind REVIEW checks behavior, not just the number. `merge_ready` → **merge-train**.

## Phase 4 — RE-BENCHMARK + loop

After each wave merges, re-measure the affected journeys TWICE on `{{BASE}}`. A journey is
within-budget only when TWO consecutive post-fix runs meet the budget (beats noise and
one-off cache warmth). A fix that measured fast once but fails the second run is NOT done —
re-diagnose. Re-baseline all journeys periodically (a fix elsewhere can regress a
neighbor). Loop until every journey is within budget or parked.

## Completion contract (evidence)

- Every critical journey: within budget confirmed by TWO consecutive measured runs
  (numbers pasted), OR PARKED with a written reason + human reference (needs an
  infra/architecture change beyond this mission's scope, or an inherent-cost tradeoff).
- Every fix PR: a measured before→after for its journey (no number → not merged); a fresh
  worker re-measures a sample to confirm the reported win reproduces.
- No fabricated metrics (the honesty rule — a fresh reviewer spot-checks a claimed number
  by re-running).
- Perf budgets added to CI where supported, so wins are regression-guarded.
- Final benchmark table pasted showing every journey within-budget or parked.
- Promotion to default is out of scope.

## RESUME

`run-blackbox` RESUME scoped to this ledger; a "within budget" claim is re-verified by
RE-MEASURING (numbers, not memory) — a claimed win with no reproducible measurement
restarts as a breach. In-flight fixes resume at their measure/fix/confirm stage.

## Anti-patterns

- Optimizing without a baseline measurement (guess-and-hope; you can't prove a win).
- One fast measurement = "fixed" (perf is noisy — two consecutive, always).
- Fabricating or estimating a number instead of measuring (the honesty rule; a spot-check
  catches it and fails the mission).
- Scattershot micro-opts instead of the profiled bottleneck (moves numbers randomly).
- A speed fix that changes behavior (that's a bug the review must catch).

## Handoff contract

Emits the perf ledger (baselines, bottlenecks, before/after, confirmations), findings in
the AGENTS.md schema, and REFLECT learnings to `fleet-memory`. Composes with
`benchmark-fleet` (measurement workers) and `canary-fleet` (post-deploy perf watch).
Schedulable via `standing-fleet` (precheck: a journey regressed past budget).

## Related

`benchmark-fleet` (the measurement fleet perf-sweep drives), `canary-fleet` (post-deploy
perf), `feature-factory` (ship perf budgets with features), `merge-train`, `fleet-doctor`,
`gate-steward`, `run-blackbox`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the journey/budget/before-after ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
