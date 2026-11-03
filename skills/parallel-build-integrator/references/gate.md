# The gate

Run it in this order before every push. Each step is cheap compared with a red main.

| # | Step | Command (from `.integrator/config.sh`) | Pass means |
|---|---|---|---|
| 1 | Regenerate | `REGEN_CMD` (env types, codegen, bundles) | `git status` shows no change, or you commit the change |
| 2 | Lint/format | `LINT_CMD` | Zero findings in the **whole** log |
| 3 | Typecheck | `TYPECHECK_CMD` | Every task passes |
| 4 | Drift | each of `DRIFT_CMDS` (API spec export, migration diff, pinned versions) | No diff, exit 0 |
| 5 | Full suite | `FRESH_DB_CMD`, then `TEST_CMD` | Only failures you have classified as below |
| 6 | Secret scan | `scripts/keyscan.sh <base>` | No matches, or every match inspected and benign |

`scripts/gate.sh` runs steps 1–5, keeps each step's full log in `$SCRATCH/gate-<step>.log`, and stops at the first failure. It prints each log's tail, but the tail is not the result. Open the lint log.

## Classifying test failures

A failure blocks the push until it is one of these:
1. **Yours, fixed:** reproduced, root-caused, fixed with a test, and re-run.
2. **Known timing failure, confirmed:** it passes when the file runs alone (`TEST_ONE_CMD <file>`), and it is on the known-flaky list with its cause written down (a 4 s kill window, a 5 s timeout under load). Keep that list short and write each cause in it.
3. **Pre-existing on main:** it fails the same way on `origin/main`. Say so in the PR.

"Flaky" is not a root cause. Timing failures that are really defects:
- **Measuring during an animation:** wait for finite animations to finish.
- **A fixed sleep racing a slow machine:** wait for a condition instead.
- **A test sharing state:** isolate it.

## Root versus CI

Agent containers often run as root, and CI runners don't. File-permission tests (mode `0500` files, unwritable homes, `0700` temp dirs) pass as root and fail in CI.
- Run those tests through `scripts/as-user.sh <user> <test command>`.
- When a test helper creates a directory that another user must traverse, give it the mode of `/tmp` (`1777`), not `0700`.

## A fresh database per full run

Owners and earlier runs fill the shared development database, and rollups and listings slow down until DB-backed tests time out. `FRESH_DB_CMD` drops and recreates a dedicated database, creates the extensions, migrates, and checks for migration drift. Point `TEST_CMD`'s env at it.

## Temp-dir hygiene

Test suites that `mkdtemp` without cleanup leave tens of thousands of directories in `/tmp`. Fix it at the runner rather than in each test: a global setup that points `TMPDIR` at one per-run directory (mode `1777`) and removes it at the end. Tests that run probes as another user still need to traverse it.

## Secret scan

`scripts/keyscan.sh <base>` scans **added lines only** of `git diff <base>..HEAD` for provider key prefixes, private-key headers, and cloud and chat tokens. It prints matches with the secret part redacted.
- **Placeholders are benign:** `sk-ant-...`, `xoxb-test-token`, and fixture values that say "fake".
- **Anything else stops the push.** Rewrite the unpushed commit, rotate the key if it ever left the machine, and tell the user.
- Allowlist known placeholders with `KEYSCAN_ALLOW` in the config.
