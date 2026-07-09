# Clean-Sweep — per-finding pipeline, ledger schema & merge ordering

## The ledger (`docs/clean-sweep-progress.md`) — your external brain

One row per fix-unit. Reconstructed after every compaction; it is the source of truth. Suggested
columns / per-row flags:

```
FU-ID  | finding IDs | branch/worktree | CODED PR_OPEN BUGBOT REVIEWED MERGED WT_CLEAN | PR# | notes
```

- **CODED** — builder finished, commits pushed, regression test added.
- **PR_OPEN** — integrator opened the PR against BASE (record PR#).
- **BUGBOT** — third-party bot ran + reconciled (valid findings folded in, commits normalized), or
  "did-not-run" logged.
- **REVIEWED** — build-blind reviewer voted PASS (FAIL → back to builder with itemized changes).
- **MERGED** — commit-preserving merge into BASE confirmed, branch deleted.
- **WT_CLEAN** — coordinator removed the worktree.

Also keep in the ledger: a **CLOSE-INDEX** (which findings map to which FU), the **collision-set
merge order** (serialized hot-file findings), and a **decisions** list (defaults you chose).

## Per-finding state machine

```
                 FAIL (itemized changes)
              ┌─────────────────────────────┐
              ▼                             │
[pending] → BUILD ─► OPEN_PR+RECONCILE ─► REVIEW ──PASS──► MERGE ─► WT_CLEAN ─► [closed]
 (codex)      │         (claude int.)      (claude rev.)   (claude int.)  (coord)
              │                                              ▲
              └── hot-file collision? rebase onto merged BASE┘ before its own merge
```

Each box is a **fresh worker session**. The builder must never be the reviewer (build-blind review
is the point). Roles map to the preamble assets:
- BUILD → `assets/builder_preamble.txt` (implement finding + real regression test, commit as maintainer).
- OPEN_PR+RECONCILE → `assets/integrator_preamble.txt`.
- REVIEW → `assets/reviewer_preamble.txt`.
- MERGE → `assets/merge_preamble.txt`.

### Reviewed-SHA invariant (MERGE stage)

The coordinator captures the **PR head SHA the reviewer graded PASS** and passes it into the merge
worker as `{{REVIEWED_SHA}}`. The merge worker MUST verify that the head of the PR branch equals
`{{REVIEWED_SHA}}` modulo author-normalization (same-tree rewrites: author/committer reset to
`{{MAINTAINER}}`, trailers stripped). Any tree-changing commit added after review — including a
"mechanical" one the worker might otherwise be tempted to author — REQUIRES re-review by a fresh
build-blind reviewer. The mechanical-fix pre-authorization applies at the INTEGRATE stage only.
This closes the hole where a worker at MERGE stage could silently land unreviewed code.

## Wave planning & collisions

- Fan out **independent** findings in bounded waves (≈3–5 concurrent workers; `max-concurrent`).
- Findings touching the **same hot files** (routers, schema, migrations, shared config, lockfiles)
  are a **collision set** — assign a strict merge order. Only the head of the set opens its PR
  against clean BASE; each subsequent one **rebases onto the just-merged BASE** and re-verifies
  before its merge.
- **DB migrations** are a guaranteed collision: two findings both emit `NNNN_*.sql`. Renumber the
  later one and update the migration journal index. Verify with a **real schema push**, not the
  schema-diff check (which misses journal/file mismatches).

## Reviewer verdict → merge gate (shared-account workaround)

On a shared GitHub identity, `gh pr review --approve` is blocked ("can't approve your own PR"). So:
1. Reviewer posts **PASS as a PR comment** (not an approval).
2. Coordinator records REVIEWED=PASS in the ledger from the reviewer's `worker_done`.
3. Merge integrator runs `gh pr merge <PR> --merge --delete-branch` — it succeeds regardless of
   GitHub's `reviewDecision`. Gate on the **coordinator's** confirmation, not GitHub's.
4. If a *required-review branch-protection rule* actually blocks merge, that's an escalation to the
   user — do not force around a real protection rule.

## Definition of done for one finding

- PR merged into BASE, commit-preserving, **every commit authored `{{MAINTAINER}}` with no trailers**.
- A regression test that **fails if the fix is reverted** is present and green.
- Bot reconciled; branch deleted; worktree removed; ledger row fully flagged.

## Definition of done for the run

- Every Lane-A finding closed (all ledger rows MERGED + WT_CLEAN).
- Anti-inflation E2E gate PASS with recorded evidence (build/type/lint/test + real-DB push +
  critical-path integration assertions).
- Lane-B decisions drafted and surfaced to the owner; Lane-0/OPS queue surfaced, not executed.
- Final report delivered; downstream human gates (BASE→default promotion, deploy) left explicitly
  unchecked.

## Anti-inflation E2E gate (Phase 4 detail)

**Green unit tests ≠ working product.** Per-PR reviews see only affected tests and miss integration
breakage. Before declaring done, dispatch ONE gate worker that, on the fully-integrated `{{BASE}}`,
runs a **fresh clean install on the pinned toolchain** and verifies against **actual result state**,
not exit codes:

- `{{BUILD}}` + `{{TYPECHECK}}` + `{{LINT}}` clean (a per-PR-passing branch can still fail a full
  typecheck — e.g. a `number|undefined` under strict indexing that affected-tests-only review missed).
- Full `{{TEST}}` suite green (the forced full-suite run also exposes order-dependent pollution;
  see `learnings.md` #37).
- If there's a DB: a **real schema push against a real database**, asserting the expected table/column
  count and that migrations are journaled (no orphan migration silently skipped).
- **Critical-path integration tests** that assert real outcomes (rollback actually prevented the
  orphan row; the kill-switch actually blocked; exactly-once delivery held) — not just that a function
  returned.

If the gate finds a real break, spawn a fix-unit, merge it, re-gate. Record the evidence in a QA doc.
**A build-breaker caught here that every per-PR review missed is the norm, not the exception** — this
gate is why the run is trustworthy.

Schedule the format-sweep as the LAST fix-unit before the gate (or expect a one-file format follow-up
after it) — a single early format-sweep leaves residual drift on files touched by later fix-units.
See `learnings.md` #36.
