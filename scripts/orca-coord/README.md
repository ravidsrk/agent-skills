# Shared Orca coordinator helpers

**We use Orca orchestration — we do not replace it.**

These helpers wrap common `orca orchestration` / terminal flows for skills in this repo.
Each Matt×Orca skill also vendors copies under `skills/<name>/scripts/` for worktree-local paths.

| File | Purpose |
|------|---------|
| `spawn_worker.sh` | terminal create → settle → dispatch --inject → Enter (claude) |
| `preflight.py` | BASE ≠ default, git/gh, optional gitleaks |
| `pm.py` | tolerant inbox/check JSON |
| `ledger-template.md` | boolean-gate ledger schema |

## Hard dependencies
- Orca runtime running
- Orchestration experimental feature enabled
- **`orchestration` skill from the Orca CLI** (command grammar)
- Worker CLIs as needed (`codex`, `claude`)

## Install Orca first
Without Orca, do not run multi-agent skills from this pack. Strategy docs alone are not a harness.
