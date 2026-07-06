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
- BUILD → your own builder brief (implement finding + real regression test, commit as maintainer).
- OPEN_PR+RECONCILE → `assets/integrator_preamble.txt`.
- REVIEW → `assets/reviewer_preamble.txt`.
- MERGE → `assets/merge_preamble.txt`.

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
