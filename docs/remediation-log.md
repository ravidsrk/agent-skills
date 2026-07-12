# Remediation log — Codex skills review

Tracks every finding from [codex-skills-review.md](codex-skills-review.md) (2026-07-11, overall 6.0/10)
to its fix. Status: `fixed` (commit landed), `planned` (assigned to a later PR), `disposition` (P2
accepted/reworded with rationale).

| Finding | Severity | Summary                                                        | Status  | Where fixed |
|---------|----------|----------------------------------------------------------------|---------|-------------|
| B1      | P1       | spawn_worker.sh fails open, forces `ready`, heartbeat ≠ accepted | fixed   | PR1: fail-closed v2, DAG-respecting --mark-ready, exit codes 0/1/2/3, behavioral tests |
| D1      | P1       | BASE ≠ default guard defeated by ref aliases                     | fixed   | PR1: canonical-name comparison in preflight.py + alias regression tests |
| D2      | P1       | design-it-thrice / model-jury worktrees lack --base-branch       | fixed   | PR1: --base-branch <BASE> pinned in both skills |
| D3      | P1       | All fleets launch workers with max bypass flags                  | fixed   | PR1: PROFILE=ro/rw/danger profiles; danger gated on ORCA_COORD_ALLOW_DANGER=1; ro declared in read-only fleets |
| D4      | P1       | Raw force-push; routine --admin merges                           | fixed   | PR1: --force-with-lease everywhere; --admin requires once-per-run human grant (ledger gate D8) |
| D5      | P2       | Read-only fleets inherit irrelevant PR preflight                 | fixed   | PR1: preflight --mode readonly + fleet launch-profile notes |
| B5      | P1       | Gates answered via terminal-send, bypassing ask/reply            | fixed   | PR1: reply --id <CURRENT> is primary (provenance); terminal-send demoted to expired-ask unblock; literal grammar in orca-coord README |
| A4      | P2       | Phantom references/learnings.md #23 in 31 launchers              | fixed   | PR1: learning moved to scripts/orca-coord/README.md; all copies regenerated |
| E2      | P1       | 96 copied helpers drifted, no propagation path                   | fixed   | PR1: scripts/sync-orca-coord.py single-source sync + --check wired into validate-skills.py |
| E3      | P2       | pm.py stops at first malformed message                           | fixed   | PR1: skip-and-count parsing, .get() defaults |
| A1/B2   | P1       | spec-to-ship contradicts its own hard-base contract              | planned | PR2 |
| A2      | P1       | Install matrix understates dependencies                          | planned | PR2 |
| A3      | P1       | matt-ship references repo-root helper paths                      | planned | PR2 |
| A5      | P2       | AGENTS.md intent map omits 11 skills                             | planned | PR2 |
| A6      | P2       | Frontmatter copy-paste artifacts                                 | planned | PR2 |
| B3      | P1       | headless-mode describes a mechanism gstack doesn't read          | planned | PR2 |
| B4      | P1       | guard-policy is advisory prose posing as enforcement             | planned | PR2 |
| B6      | P2       | Generic preambles lack skill-specific completion contracts       | planned | PR2 |
| C1      | P1       | review-matrix invokes nonexistent Matt /code-review modes        | planned | PR2 |
| C2      | P1       | architecture-sprint skips /to-spec                               | planned | PR2 |
| C3      | P1       | review-prod-fleet "do not fix" vs fix-first gstack /review       | planned | PR2 |
| C4      | P1       | gstack-ship-fleet duplicates then invalidates review work        | planned | PR2 |
| E1      | P1       | Review ownership unpartitioned, no finding schema                | planned | PR2 |
| E4      | P2       | Related sections define no handoff contract                      | planned | PR2 |

New capability work (not review findings): PR3 adds standing-fleet, fleet-doctor, run-blackbox,
gate-steward, merge-train; PR4 adds quorum, spec-decompose, ephemeral-fleet, fleet-memory and deepens
qa-fleet / ios-qa-fleet.

Per-PR Codex verdicts live in [reviews/](reviews/).
