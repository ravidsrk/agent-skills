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
| A4      | P2       | Phantom references/learnings.md #23 in 31 launchers              | fixed   | PR1 (two steps): pointer first moved to scripts/orca-coord/README.md — re-review rated that NOT-FIXED for standalone installs — then closed by vendoring README.md beside every launcher (sync MANIFEST). docs/reviews/codex-pr1.md records both rounds. |
| E2      | P1       | 96 copied helpers drifted, no propagation path                   | fixed   | PR1: scripts/sync-orca-coord.py single-source sync + --check wired into validate-skills.py |
| E3      | P2       | pm.py stops at first malformed message                           | fixed   | PR1: skip-and-count parsing, .get() defaults |
| A1/B2   | P1       | spec-to-ship contradicts its own hard-base contract              | fixed   | PR2: own vendored preflight path; 'Orca or similar' removed; lightweight mode on same-worktree Orca workers + build-blind combined-PR review |
| A2      | P1       | Install matrix understates dependencies                          | fixed   | PR2: tracks install gstack/Matt for real; scoped no-dependency claim; AGENTS.md runtime dependency matrix; composer skills declare Requires |
| A3      | P1       | matt-ship references repo-root helper paths                      | fixed   | PR2: skill-local scripts/ paths with canonical pointer |
| A5      | P2       | AGENTS.md intent map omits 11 skills                             | fixed   | PR2: all 11 rows added |
| A6      | P2       | Frontmatter copy-paste artifacts                                 | fixed   | PR2: matt-ship, wayfinder-fleet, design-it-thrice |
| B3      | P1       | headless-mode describes a mechanism gstack doesn't read          | fixed   | PR2: GSTACK_HEADLESS env via launcher overrides; correct blocking semantics; auto-decide attributed to autoplan coordinator |
| B4      | P1       | guard-policy is advisory prose posing as enforcement             | fixed   | PR2: real /guard + /freeze hooks for claude workers, sandbox profiles for codex, danger forbidden, ADVISORY ONLY banner without gstack, precedence rules |
| B6      | P2       | Generic preambles lack skill-specific completion contracts       | fixed   | PR2: checkable completion contracts in health, benchmark, docs, design-shotgun fleets (worst four) |
| C1      | P1       | review-matrix invokes nonexistent Matt /code-review modes        | fixed   | PR2: own axis rubrics or one full /code-review run; matt-ship Phase 6 same |
| C2      | P1       | architecture-sprint skips /to-spec                               | fixed   | PR2: TO-SPEC phase inserted before /to-tickets |
| C3      | P1       | review-prod-fleet "do not fix" vs fix-first gstack /review       | fixed   | PR2: /review axis removed; report-only with ro workers |
| C4      | P1       | gstack-ship-fleet duplicates then invalidates review work        | fixed   | PR2: consumes review artifacts via reviewed-SHA freshness; no pre-run test/review workers |
| E1      | P1       | Review ownership unpartitioned, no finding schema                | fixed   | PR2: AGENTS.md routing table + JSON finding schema + reviewed-SHA handoff rule |
| E4      | P2       | Related sections define no handoff contract                      | fixed   | PR2: handoff contracts in review-matrix, review-prod-fleet, full-sprint-fleet |

New capability work (not review findings): PR3 adds standing-fleet, fleet-doctor, run-blackbox,
gate-steward, merge-train; PR4 adds quorum, spec-decompose, ephemeral-fleet, fleet-memory and deepens
qa-fleet / ios-qa-fleet.

Per-PR Codex verdicts live in [reviews/](reviews/).
