# Codex review — PR2 (contracts, truthfulness, policy)

Reviewer: codex exec, gpt-5.6-sol, read-only sandbox. Date: 2026-07-12.
Scope: git diff main...HEAD on ravidsrk/fleet-contracts.

Round 1 verdict: MERGE-READY NO — 3 P1 (autoplan headless AUTO_DECIDE contradiction,
routing-table vs ship-fleet 'Never' cell, spec-to-ship README --admin without D8 grant)
+ 5 P2 (Track D matrix row, missing test-adequacy axis, overgeneralized full-sprint
handoff, 12 README 'call Orca' comments, rerun-unsafe clone snippet). All fixed.

Round 2 (focused): P1-1 still PARTIAL — categorical 'gstack does not self-answer'
contradicts upstream plan-tune AUTO_DECIDE preference handling. Fixed with the layered
model (preference-first, one-way-door override, headless blocks untuned).

Round 3: preferences are PROJECT-persistent, not session-scoped; last categorical
line removed. Final verdict:

MERGE-READY: YES — both files correctly describe preference-first handling, one-way-door override, project-persistent storage, and blocking for untuned headless questions.
