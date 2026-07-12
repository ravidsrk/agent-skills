# Shared Orca coordinator helpers

**We use Orca orchestration — we do not replace it.**

These helpers wrap common `orca orchestration` / terminal flows for skills in this repo.
This directory is the SINGLE SOURCE OF TRUTH. Each fleet skill vendors generated copies
under `skills/<name>/scripts/` for worktree-local paths — edit here, then run
`python3 scripts/sync-orca-coord.py` to regenerate every copy (`--check` verifies drift;
`scripts/validate-skills.py` runs the check automatically).

| File                 | Purpose                                                              |
|----------------------|----------------------------------------------------------------------|
| `spawn_worker.sh`    | fail-closed dispatch: create → settle → verify ready → inject → Enter |
| `preflight.py`       | BASE ≠ default on canonical refs, git/gh, `--mode readonly`, gitleaks |
| `pm.py`              | tolerant inbox/check JSON (skips malformed segments)                  |
| `ledger-template.md` | boolean-gate ledger schema                                            |

## spawn_worker.sh v2 contract

- Exit codes: `0` dispatched + heartbeat, `1` step failed, `2` usage/policy refusal,
  `3` dispatched but no heartbeat (respawn in a FRESH terminal — see Learnings).
- Never forces `task-update --status ready`; `--mark-ready` is an explicit opt-in that
  only applies when every declared dep is completed. The DAG stays authoritative.
- `PROFILE=ro|rw|danger` selects the worker launch command:
  - `ro`     → `codex --sandbox read-only` / `claude --permission-mode plan` (report-only fleets)
  - `rw`     → `codex --sandbox workspace-write` / `claude --permission-mode acceptEdits` (default)
  - `danger` → the bypass flags, ONLY with `ORCA_COORD_ALLOW_DANGER=1` (worktree-isolated,
    disposable, or ephemeral-sandbox work)
  `CLAUDE_CMD` / `CODEX_CMD` override the profile entirely when set.

## Hard dependencies

- Orca runtime running
- Orchestration experimental feature enabled
- **`orchestration` skill from the Orca CLI** (command grammar)
- Worker CLIs as needed (`codex`, `claude`)

## Learnings (operational, hard-won)

- **L1 — `dispatch --inject` pastes but does not SUBMIT on claude workers.** codex terminals
  auto-submit; claude does not. After inject, wait ~8s, then `orca terminal send --terminal <h>
  --enter`. An extra Enter to an already-submitted worker is harmless. `spawn_worker.sh` bakes
  this in with a 3× heartbeat-verify retry.
- **L2 — Re-dispatching to the SAME handle is a no-op.** A handle that already had this task
  returns dispatch id `null` and does nothing. To recover a worker that never heartbeated,
  create a FRESH terminal and dispatch there (fresh dispatch context). This is why
  `spawn_worker.sh` exits `3` instead of retrying in place.
- **L3 — Orca worktree IDs are composite `uuid::path`.** `orca terminal create --worktree
  id:<uuid>` fails with `selector_not_found`. Pass `--worktree "path:/abs/worktree/path"`
  (unambiguous) or the full composite id. `spawn_worker.sh` takes a RAW selector.
- **L4 — `check --wait` returns one message at a time; `{count:0}` is a checkpoint, not a
  failure.** If N workers can finish together, loop N times. Timeouts mean "nothing yet".

## Install Orca first

Without Orca, do not run multi-agent skills from this pack. Strategy docs alone are not a harness.
