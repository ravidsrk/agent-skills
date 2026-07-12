---
name: quorum
description: >-
  N-voter consensus on Orca group fan-out: broadcast a question to @claude / @codex /
  @idle with a shared thread, reduce the replies to a consensus table, and turn
  disagreement into a gate-steward taste gate — or run full independent JURY tasks for
  redundant execution. Use when you want multiple independent opinions ("get a second
  opinion from every idle agent", vote on a finding, adversarial verification, model
  jury), consensus before an expensive step, or cross-model disagreement surfaced
  instead of averaged away.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Multiple worker
  agents installed (codex/claude at minimum) for cross-model votes.
---

# Quorum — votes are cheap, disagreement is signal

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | group addresses (@all/@idle/@claude/@codex/…), shared `thread_id` fan-out, threads, tasks | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the vote protocol + reduction rules | this repo |

**Runtime facts this protocol is built on:** group `send` fans out one message per
recipient sharing a `thread_id`, excluding the sender; an unknown/empty group errors;
`ask` REJECTS group addresses (the runtime's own hint: use `send --type decision_gate`
for fan-out); `worker_done`/`heartbeat` cannot be group-addressed.

## Mode 1 — VOTE (judge an artifact; minutes, not hours)

For judging something that already exists: a finding, a diff, a design doc, a plan.

```
1. FRAME   — ONE self-contained ballot. The voters share no context with you:
             paste the artifact (or its path), the question, the options, and the
             required reply format:
             "REPLY on this thread with: VOTE=<A|B|abstain> · CONFIDENCE=<1-5> ·
              one-paragraph rationale. Vote to REFUTE unless the evidence convinces you."
2. CAST    — mint a QUORUM-ID (QID, e.g. q-<date>-<slug>) and put it in the subject:
             orca orchestration send --to @idle --type decision_gate \
               --subject "quorum <QID>: <question>" --body "<ballot — voters MUST echo <QID> in their reply>"
             A cross-model panel (--to @claude AND --to @codex) is TWO sends and
             therefore TWO thread_ids — the QID is what unifies them. Sum the recipients
             across all fan-outs: that is your denominator. Zero recipients on a fan-out
             throws: spawn idle voters first.
3. COLLECT — poll `inbox --full --json` + pm.py; a vote counts iff it is a reply on one
             of THIS quorum's threads AND echoes the QID (belt and braces — replies
             stay per-thread, the QID spans them). Deadline, not forever: one re-nudge
             per thread at T/2, close the poll at T. Late votes are noted, not counted.
4. REDUCE  — mechanically, no re-judging:
             | voter | model | vote | confidence | one-line rationale |
             Quorum rule declared UP FRONT (default: majority of votes cast, minimum 2
             votes, abstentions excluded). Refute-framing means ties/short quorum = NOT
             confirmed.
5. ROUTE   — unanimous → act on it. Split → this is a TASTE gate: hand the table to
             gate-steward (steward recommendation + pending-veto brief), or to the human
             when the underlying action is one-way. Never average a split into a "2.5".
```

## Mode 2 — JURY (redundant independent execution; expensive, use deliberately)

The `model-jury` pattern, generalized: N workers independently produce the SAME
deliverable (implementation, RCA, design), then a VOTE round judges the candidates.

```
1. one task-create per juror — same acceptance criteria verbatim, ISOLATED worktrees
   (`--base-branch <BASE>` pinned), different agents (claude/codex/…).
2. dispatch each via scripts/spawn_worker.sh; collect worker_done + reportPaths.
3. VOTE mode (above) on the candidates, voters ≠ authors (a juror never votes on its
   own candidate — check handles).
4. The winner pick is ALWAYS a human gate (matching `model-jury`): jury candidates are
   code that will merge — consequential by definition. The consensus table informs the
   human; the steward never auto-picks a jury winner, unanimous or not.
```

Cost warning up front: JURY = N× the work + a vote round. Reach for it on decisions
whose failure cost dwarfs the spend (core module shape, irreversible data migration
strategy), not routine tickets.

## Completion contract

A quorum is DONE when the ledger holds: the ballot verbatim, the recipient count
(denominator), every reply row (or "no reply by deadline" per silent voter), the reduction
table, the declared quorum rule, and the routed outcome (acted / taste-gated / parked).
A vote you can't audit from the ledger didn't happen.

## Rules

- Voters get the refute framing by default — agreeable panels are worthless.
- The coordinator reduces; it never votes in its own quorum.
- Denominator honesty: "2 of 2 voted A" and "2 of 7 voted A, 5 silent" are different
  results — always report both numbers.
- Cross-model (@claude + @codex) beats same-model N when the question is judgment;
  same-model N is fine for repro/verification legwork.

## Handoff contract

Emits the consensus table into the run ledger (and `report_path` when standalone).
Split votes route to `gate-steward` as taste gates; `clean-sweep` adversarial
verification and `model-jury` candidate picks consume VOTE mode directly.

## Related

`model-jury` (the JURY special case, now routed through this protocol), `gate-steward`,
`adversarial-ticket`, `review-matrix`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the quorum tables extend

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
