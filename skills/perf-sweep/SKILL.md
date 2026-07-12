---
name: perf-sweep
description: >-
  Autonomous mission: bring every critical user journey within its performance budget.
  Baseline each journey with real measurement (Core Web Vitals / server timings), fix
  budget breaches PR-per-hotspot with a before/after number, re-benchmark to each
  metric's measurement contract (percentile sample, lab median-of-5, field window), and
  loop until every journey is within budget or parked with a reason. Use when "the app is slow", perf sweep,
  performance budget, Core Web Vitals, "get under budget", or an unattended
  performance-hardening run. Measure-first — never guess-and-optimize.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; a way to
  MEASURE (Lighthouse/DevTools MCP for web CWV, or a server/profiler harness). Worker
  playbooks: addyosmani/agent-skills (performance-optimization, web-performance-auditor,
  browser-testing-with-devtools) or gstack (benchmark, browse daemon) — one router per
  worker. In-pack: merge-train, run-supervision, gate-steward, spec-decompose, fleet-memory.
---

# Perf-Sweep — every journey within budget, proven by a before/after number

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE: every
critical journey meets its declared budget, proven by MEASURED before/after numbers taken
to that metric's measurement contract (below) — a p95 needs its request sample, a field
CWV its window; two lab runs are a smoke minimum, not universal proof. Guessing at
optimizations, or confirming a metric with a protocol weaker than it needs, are both
banned — the metric is the mission.

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
ORIENT → declare metric contract → BASELINE every journey → rank breaches by gap×traffic
  → DIAGNOSE hotspot (profile, find the actual bottleneck) → FIX (PR-per-hotspot, before/after)
  → build-blind REVIEW → merge-train → RE-BENCHMARK (to the metric's contract) → loop → REFLECT
```

## The measurement contract (declare per metric BEFORE baselining)

"Two runs" is a smoke minimum, not proof — a p95 or a field Core Web Vital needs a real
sample, and lab ≠ field. Fix the protocol per metric in the ledger up front, and use it
identically for baseline and candidate:

| Metric kind | Source | Sample / confirmation | Conditions to pin |
|-------------|--------|-----------------------|-------------------|
| Field CWV (LCP/INP/CLS) | RUM / CrUX / field beacon | the metric's own percentile (p75) over a stated window + sample count; a "run" is a window, not a page-load | real traffic; don't substitute a lab number |
| Lab CWV (Lighthouse) | Lighthouse/DevTools, lab | median of ≥5 runs (not 2); report the spread | throttling preset, cold-vs-warm cache, device/network profile |
| Server latency percentile (p95/p99) | load harness | the percentile over ≥N requests at stated concurrency, two independent load runs agree | concurrency, warm/cold, dataset size, same env |
| Simple duration (mean) | benchmark harness | median of ≥5, two consecutive agree | isolation, warmup discarded |

A metric measured against a protocol weaker than its row (a p95 "confirmed" by 2 page
loads, a field CWV proxied by one Lighthouse run) is NOT confirmed. Baseline and candidate
MUST share source, sample size, and pinned conditions — a lab-vs-field or warm-vs-cold
comparison is not a delta.

## Phase 1 — BASELINE (measure to the contract, don't assume)

- `PROFILE=ro` worker per journey measures per its metric's contract row (NOT a blanket
  "twice" — a p95 gets its request sample, a field CWV its window). Record the value + the
  breach. **Metric-honesty rule (the web-performance-auditor law): never fabricate or
  proxy a number.** A journey you couldn't measure to its contract is `unmeasured`,
  flagged for a human — not assumed-fine, and not downgraded to a weaker proxy.
- Ledger (`docs/perf-sweep-progress.md`): `| journey | metric+contract | budget | baseline |
  breach | bottleneck | FIXED | before→after | PR | MERGED | CONFIRMED | outcome |`.
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

After each wave merges, re-measure the affected journeys ON `{{BASE}}` to their metric
contract (same source, sample, and pinned conditions as the baseline). A journey is
within-budget only when the contract's confirmation is met (median-of-5 for lab, the
percentile over the request sample for p95, the window for field CWV — not a lucky single
run). A fix that met budget once but fails the contract's confirmation is NOT done —
re-diagnose. Re-baseline all journeys periodically (a fix elsewhere can regress a
neighbor). Loop until every journey is within budget or parked.

## Two named terminal outcomes

- **WITHIN-BUDGET** — every critical journey meets its budget on its metric contract's
  confirmation. A completed mission.
- **OPTIMIZED-WITH-PARKED** (degraded, not WITHIN-BUDGET) — all fixable hotspots fixed, but
  ≥1 journey stays over budget needing an infra/architecture change beyond scope, or is
  an inherent-cost tradeoff, parked with a human reference. Legitimate stop, never reported
  as WITHIN-BUDGET.

## Completion contract (evidence — the outcome must be named)

- Ledger outcome line = `WITHIN-BUDGET` or `OPTIMIZED-WITH-PARKED` with the parked list.
- Every critical journey: within budget confirmed to its metric contract (source, sample,
  conditions, and the pasted numbers), OR PARKED with a written reason + human reference (needs an
  infra/architecture change beyond this mission's scope, or an inherent-cost tradeoff).
- Every fix PR: a measured before→after for its journey (no number → not merged); a fresh
  worker re-measures a sample to confirm the reported win reproduces.
- No fabricated metrics (the honesty rule — a fresh reviewer spot-checks a claimed number
  by re-running).
- Perf budgets added to CI where supported, so wins are regression-guarded.
- Final benchmark table pasted showing every journey within-budget or parked.
- Promotion to default is out of scope.

## RESUME

`run-supervision` RESUME scoped to this ledger; a "within budget" claim is re-verified by
RE-MEASURING (numbers, not memory) — a claimed win with no reproducible measurement
restarts as a breach. In-flight fixes resume at their measure/fix/confirm stage.

## Anti-patterns

- Optimizing without a baseline measurement (guess-and-hope; you can't prove a win).
- Confirming a metric below its contract (a p95 "proven" by 2 page loads, a field CWV by
  one lab run) — meet the metric's own protocol or it isn't confirmed.
- Fabricating or estimating a number instead of measuring (the honesty rule; a spot-check
  catches it and fails the mission).
- Scattershot micro-opts instead of the profiled bottleneck (moves numbers randomly).
- A speed fix that changes behavior (that's a bug the review must catch).

## Handoff contract

Emits the perf ledger (baselines, bottlenecks, before/after, confirmations), findings in
the AGENTS.md schema, and REFLECT learnings to `fleet-memory`. Composes with
`gstack-fleet` (benchmark/measurement + post-deploy perf watch).
Schedulable via `standing-fleet` (precheck: a journey regressed past budget).

## Variants (absorbed skills)

- **mode=report-only** (was `benchmark-fleet`): measure critical journeys vs baseline and report, no fix loop. This is Phase 1 alone, `PROFILE=ro`.

## Related

`gstack-fleet` (post-deploy perf watch), `spec-to-ship` (ship perf budgets with features),
`merge-train`, `run-supervision`, `gate-steward`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the journey/budget/before-after ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
