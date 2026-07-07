# Ledger template — the coordinator's external brain

Keep this as `docs/build-progress.md` on the integration branch. Update at: task start, every
`worker_done`, and before/after every merge + cleanup. A FRESH coordinator with zero context must resume
from this file alone. Commit + push it periodically (rebase onto remote base first — gotcha #12).

```markdown
# Build Progress Ledger — Coordinator External Brain

## PHASE: BUILDING
Lifecycle: THINK ✓ → PLAN ✓ → PLAN_FROZEN ✓ → **BUILDING** → TESTING → SHIPPING → REFLECTING → DONE

## Orientation (resolved)
- REPO_ROOT / SELECTOR (Orca repo id) / MAINTAINER (name+email, authors every commit, no trailers)
- BASE = <integration branch> off <default>@<sha>
- REQ_DOCS = <spec paths> (READ-ONLY truth); gh authed; gitleaks present; runtime ready
- BUGBOT: on/off (if on, integrator runs wait→ingest→reconcile every PR + re-push)

## Decisions (rationale, one line each) — see DECISIONS.md
- D1 stack … / D2 worker config … / D6 sync-local-base-before-wave … / D7 answer-gates-via-terminal-send
- D8 merge-trap: merge via --admin once gates green + review concluded; VERIFY state=MERGED

## Task ledger  (boolean gates advance a task only when TRUE in this file)
| Task | deps | lane | mig# | req IDs | WT | flags | PR# | notes |
|------|------|------|------|---------|----|-------|-----|-------|
| F1 scaffold | — | A | — | R77,N16 | cleaned | BUILT=t PR_OPEN=t BUGBOT=t REVIEWED=t MERGED=t WT_CLEAN=t | #12 | verified on base |
| S3 orchestrator | F1,F3,F5 | A | 0007 | R6,R7 | id:…/s3 | DISPATCHED (task_… → term_…) | — | building |
| … | | | | | | | | |

lane: A=implement · B=draft+gate (load-bearing judgment → human) · 0=refuse+surface (real creds/prod/OPS)
mig#: pre-assigned migration number for migration-touching tasks (renumber-on-rebase — gotcha #14).

## RECONCILED CURRENT STATE  (authoritative — rewrite this block wholesale from git; don't trust stale cells)
<!-- RECONCILED-STATE-START -->
Reconciled against `origin/<BASE>` at <sha>. Git is truth; this block is the cache.
- MERGED (verified on base): <task → PR# → sha>
- IN-FLIGHT: <task → phase → PR#/WT>
- Chain-file queues (serialized): route-registry: <t,t> · approval-gate: <t> · migrations: <lane order>
<!-- RECONCILED-STATE-END -->
Rewrite this whole block from a git grep each cascade (gotcha #15) — do NOT regex individual rows.

## Wave state
- MERGED: <list> · IN-FLIGHT: <task → phase> · NEXT-READY: <unblocked tasks> · HOT-FILE queue: <serialized>

## CONTEXT-HANDOFF block (fill on context pressure, then shift-change)
- Live dispatches: taskId/dispatchId/branch/PR/WT per in-flight task
- Next wave + open questions with default-derived answers
- The critical ops rules (gotchas) a fresh coordinator must not relearn the hard way
```

## Boolean gates, defined

- **BUILT** — builder pushed a real slice with failing-without-impl tests, gates green.
- **PR_OPEN** — PR opened against BASE, number recorded.
- **BUGBOT** — the second bot ran (or the cap elapsed, logged); its comments addressed/dismissed and any
  pushed commits normalized + green. Auto-true if no bot.
- **REVIEWED** — a fresh build-blind reviewer approved (verified acceptance, real tests, no stub, no leak).
- **MERGED** — **verified** `state=MERGED` + a real file from the PR present on BASE (not a worker claim).
- **WT_CLEAN** — worktree removed after the verified merge + branch deletion.

A task is terminal only when all six are TRUE (or BLOCKED with a recorded reason). **MERGED** now means the
full merge-verify: `state=MERGED` AND `baseRefName==<BASE>` AND a real file from the PR greppable on
`origin/<BASE>` (gotchas #1, #13) — never a worker's word. Terminate the whole run only when: every planned
task terminal; every requirement DONE/PARTIAL/DEFERRED/BLOCKED in the traceability report; **the
anti-inflation e2e gate passed with its negative controls reddening (teeth), and every adversarial
(Z-suite) P0 finding is fixed-in-branch + ratcheted** (see `references/verification.md`); and ship +
reflection + backlog artifacts exist.

## OPS / human queue (things no agent can do — surface, never fake)
- Rotate any secrets exposed in chat. · License/legal sign-offs that gate vendoring. · Real credential /
  account provisioning. · Live deploy/apply (merge ≠ deploy). · **Promotion PR** (integration BASE →
  default branch) — the swarm OPENS it for human review, never self-merges it. Track in
  `docs/ops-actions.md`; names only, never secret values.

## REFLECT artifacts (produced before DONE)
- `docs/reports/build-complete.md` (what shipped) · `traceability.md` (every req → task → PR, verified) ·
  `go-live-runbook.md` (the OPS steps to actually deploy). Plus `backlog.md` (deferred/nice-to-have) and
  the promotion PR opened against the default branch for human review.
