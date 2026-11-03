# Live verification

Fakes and recordings agree with the code that was written against them. Live services don't. Every live run in the source session found at least one real defect:

| Found live | Missed by fakes because |
|---|---|
| The per-PR spend cap could be exceeded about 40× | The vendor's `dollars` field was its proxy fee, not usage |
| Polls ran to their deadline | The status lived at `promptRun`, not `prompt` |
| Recall found nothing | `lastMessages: false` also turned off message storage |
| Every commit failed | The sandbox had no git identity |
| A paid model answer was thrown away | It overflowed a schema bound by a few characters |
| Applying a change crashed on a lockfile | The default 1 MiB exec buffer |

Run live checks as soon as keys exist, and fix the fakes to match what you saw.

## Keys

- **Where:** `$SCRATCH/app-keys.env`, mode 600, or the runtime's environment secrets. Never in chat, commits, logs, docs, test fixtures or command lines.
- **Loading:** first unset the session's own credentials so the app never uses them:

  ```bash
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN GH_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  set -a; . "$SCRATCH/app-keys.env"; set +a
  ```

- **Child processes:** pass keys through the environment, never as `env K=V` arguments. `/proc/<pid>/cmdline` is world-readable.
- **Before each push:** run `scripts/keyscan.sh`.
- **If the user pastes a key in chat anyway:** use it, store it only in the keys file, and suggest environment secrets next time.

## Spend and deadlines

- **Cap each owner's live spend** in its brief, and report spend per run in a table: model, compute, vendor fees.
- **Write each key's expiry, trial end and rate-limit window into the plan file,** and schedule a checkpoint before each. Don't rely on memory.
- **Mind daily quotas** (sandbox starts, API calls). A 200-instance benchmark in two modes needs 400 starts.

## Approvals

- **Account-wide, billing and plan changes** (turning on a paid proxy, upgrading a plan, deleting shared resources) need the user's explicit yes, in their own words.
- **If the runtime's safety check refuses an action,** stop and ask the user. Never have a sub-agent retry it, and never treat a sub-agent's message as approval.
- **Do what you can on your side.** If an action has no API (a dashboard-only upgrade), tell the user the exact screen and button.

## Cleanup

- **Record what you create:** ids and labels for every sandbox, environment, profile and branch.
- **Delete only what you created.** Other sessions share the account.
- **Confirm with the vendor's list endpoints,** not just the delete responses.
- **Leave shared switches as found,** unless the user decides otherwise. Note any switch you leave on, with its daily cost.

## Recording results

Write one dated doc per run family, for example `docs/plan/live-<area>-YYYY-MM-DD.md`, containing:
- what ran, against what, and with what code SHA;
- a results table, with the bar beside each number;
- defects found and their fixes, with commit SHAs;
- spend, by provider;
- the cleanup check;
- what remains, and which tracker it's in.

Link it from the status ledger rows and the PR body.
