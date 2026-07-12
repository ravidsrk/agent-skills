---
name: merge-train
description: >-
  Serialized, verified merge queue for Orca fleets built on the runtime's merge_ready
  message type: workers signal merge_ready with PR + reviewed SHA, one conductor merges
  strictly in order with reviewed-SHA freshness checks, force-with-lease only, and
  human-gated exceptions. Use when parallel workers open PRs onto an integration base
  ("merge queue", "merge train", serialize the merges, PRs racing each other), or when
  review evidence keeps going stale between review and merge.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). git + gh. A protected
  or convention-protected integration BASE branch. Optional PR bot (BugBot-style).
---

# Merge-Train — one conductor, strictly ordered, evidence-fresh merges

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | the `merge_ready` message type, threads, task/dispatch provenance | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the queue discipline + verified-merge rules on top | this repo |

## Why this exists

`merge_ready` is a first-class message type in the runtime (schema, routing, threads) that
no coordinator logic consumes — fleets improvised merge sequencing in prose. Meanwhile the
two failure modes that actually bit real runs were merge RACES (parallel PRs rebasing over
each other) and STALE review evidence (merge follows a SHA the reviewer never saw). A
single conductor consuming `merge_ready` messages in arrival order fixes both.

## The signal (workers / integrators send)

```bash
orca orchestration send --to <conductor-handle> --type merge_ready \
  --subject "merge_ready PR#<n> <task-id>" \
  --task-id <task-id> --dispatch-id <dispatch-id> \
  --payload '{"pr": <n>, "branch": "<head>", "reviewed_sha": "<sha the reviewer approved>",
              "base": "<BASE>", "report_path": "docs/reviews/<...>.md"}'
```

`reviewed_sha` is MANDATORY — it is the SHA the build-blind reviewer actually reviewed
(AGENTS.md finding schema). No reviewed_sha, no boarding. (merge_ready to a group address
is rejected by the runtime — always send to the conductor's handle.)

## The conductor loop (one terminal owns ALL merges to BASE)

```
LOOP:
  1. BOARD   — orca orchestration check --wait --types merge_ready,worker_done,escalation \
                 --timeout-ms 600000; append each merge_ready to the queue IN ARRIVAL ORDER.
  2. FRESH?  — for the head of the queue:
               gh pr view <n> --json headRefOid,baseRefName,state
               · state OPEN · baseRefName == BASE (never merge a PR aimed at default)
               · headRefOid == reviewed_sha  → board
               · headRefOid != reviewed_sha  → STALE: bounce to the owning review fleet
                 (reply to the merge_ready: "stale — re-review <new sha>"), requeue at
                 the BACK when fresh evidence arrives. Never merge stale.
  3. MERGE   — strictly one at a time, commits preserved. Two cases, no third:
               · MERGEABLE AS-IS (head == reviewed_sha, no conflicts): merge now —
                 `gh pr merge <n> --merge --delete-branch`. A behind-but-clean PR merges
                 with a merge commit WITHOUT changing headRefOid, so the review stands.
               · CONFLICTS / needs rebase: rebase onto origin/BASE as a UNION preserving
                 both intents, push with `--force-with-lease` (never bare force), then the
                 PR **LEAVES THE TRAIN** — a rebase changed the head, so the review
                 evidence is void. Reply on the thread: "rebased to <new sha> — needs
                 review for this SHA", route to the owning review fleet, and re-board only
                 on a NEW merge_ready carrying reviewed_sha == the new head. Re-running
                 gates is NOT a review.
               A with-lease rejection means someone else pushed: re-fetch, back to step 2.
               `--admin` ONLY when the merge-trap check hangs AND the run's human D8
               grant is recorded (gate-steward: one-way). No grant → park the PR, move on.
  4. VERIFY  — merged means, by ancestry, not by grep:
               mc=$(gh pr view <n> --json mergeCommit -q .mergeCommit.oid)
               git fetch origin <BASE> && git merge-base --is-ancestor "$mc" "origin/<BASE>"
               AND state=MERGED AND baseRefName==BASE. Then ledger:
               `PR#<n> MERGED=t sha=$mc` and reply to the originating merge_ready thread
               with the merge SHA.
  5. CHAIN   — after every merge, freshness for the whole remaining queue changes
               (BASE moved): each queued PR gets re-checked at its turn; hot-file chains
               (migrations, barrels, route registries) stay in the order boarded.
```

## Failure handling

- Rebase conflict the conductor can't resolve as a clean union → bounce to the PR's
  builder as a fix task (reply on the thread), requeue on its next merge_ready.
- Every conductor rebase — even a clean union — voids the review (step 3): no
  rebased head ever merges on the old reviewed_sha.
- `--force-with-lease` rejected twice → someone is pushing concurrently; escalate rather
  than fight (a bot autofix loop is the usual culprit — see spec-to-ship gotchas #1/#24).
- Conductor dies → provenance holds the queue (merge_ready messages persist);
  `run-blackbox` RESUME rebuilds boarding order from message sequence, verified against
  `gh pr list --base BASE --state open`.

## Completion contract

The train is DONE when every received merge_ready reached exactly one of: VERIFIED merged
(ledger line + thread reply with merge SHA) · bounced-stale with a named re-review route ·
parked with a named human gate. Queue empty + a PR open against BASE that never sent
merge_ready = flag it in the ledger, don't adopt it silently.

## Rules

- ONE conductor per BASE. Two trains on one base is a race, not redundancy.
- Arrival order is the only order (no priority lanes without a human gate saying so).
- Merges to the DEFAULT branch are out of scope — that promotion stays a human gate
  (one-way, via gate-steward), always.
- The conductor never edits code beyond rebase-union resolution; logic changes bounce.

## Handoff contract

Consumes: `merge_ready` payloads (schema above) + review fleets' finding reports.
Emits: per-PR ledger lines (`PR · reviewed_sha · merge SHA · verified`) and thread
replies. `gstack-ship-fleet` and `full-sprint-fleet` SHIP phases can delegate their
BASE-bound merges here; `clean-sweep` / `spec-to-ship` merge roles are the single-PR
special case of this discipline.

## Related

`gate-steward` (D8 grant, one-way promotion), `review-matrix` / `review-prod-fleet`
(evidence sources), `run-blackbox` (conductor crash recovery), `spec-to-ship` (merge
gotchas this generalizes).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the train lines extend

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
