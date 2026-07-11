# Ready-agent-drain — resume + bad briefs

## Ledger
Use `references/ledger-template.md` at `docs/ready-agent-drain-progress.md`.  
Resume by re-reading ledger + `orca orchestration task-list --json`.

## Batch size
Default max 3 concurrent. One batch per invocation if used from cron/automation.

## Garbage briefs
If agent brief is missing, contradictory, or lacks acceptance criteria:
1. Do **not** invent scope  
2. `decision_gate` / re-queue to `needs-triage` via human  
3. Prefer `triage-to-fleet` over silent implement  

## Blocked-by
Skip issues whose blockers are open. Never force-order by issue number alone.

## Close policy
Comment PR link on issue. Close only per repo policy (often on default-branch merge, not BASE merge).
