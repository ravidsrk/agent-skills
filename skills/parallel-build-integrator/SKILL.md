---
name: parallel-build-integrator
description: >-
  Turns a large GitHub backlog into merged, green PRs by running one owner agent per epic in parallel git worktrees and integrating their hand-backs on one branch. The integrator briefs each owner, cherry-picks the work, resolves docs-table conflicts row by row, gates every push (full lint output, types, drift, the full suite on a fresh database, a secret scan, a non-root check), shepherds the PR through CI and review bots, and closes each issue once its code is complete. Live checks that need outside accounts move to tracker issues, and live runs with real keys are capped and cleaned up. Use when the user says "build everything end to end", "run agents in parallel per epic", "don't ask me, review and merge the PRs yourself", "integrate the agents' work", "close the completed issues", "keep refreshing against main", or hands over a backlog of issues to finish autonomously.
license: MIT
compatibility: Requires git (worktrees), bash, python3, and an agent runtime that can start sub-agents in isolated worktrees (Claude Code's Agent tool). GitHub through the gh CLI or a GitHub MCP server. Optional runuser (non-root test runs) and a local Postgres or other per-run database.
metadata:
  version: "1.0.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit Glob Grep Agent
---

# Parallel Build Integrator

One agent can't build a 100-issue backlog in a day, but six owner agents can, provided one integrator turns their work into green PRs. The hard part isn't writing code. It's integration: owners collide in shared docs, a single unread lint line turns main red, a test that passes as root fails in CI, a PR merges before its last push lands, and live checks find bugs that every fake missed. This skill is the integrator's loop, distilled from a session that took a 133-issue backlog to three open trackers in one day with fourteen epics closed.

**You are the integrator.** Owners write code in their own worktrees and hand back commit SHAs. Only you push, open PRs and close issues.

# When to use

- A backlog of GitHub issues, grouped into epics, to build end to end
- The user wants parallel agents and autonomy ("review and merge them yourself")
- Several agents' work must land on one branch without breaking main
- Issues must close as code-complete, while outside-resource checks stay tracked

# When NOT to use

- Driving one half-built product to launch-readiness with a frozen definition of done: use `finish-line`
- A single feature or bug: just do it
- Repos without CI or tests: the gate is the point; set them up first

# Setup

1. Copy `templates/config.sh` to `.integrator/config.sh` in the project and fill in the project's real commands: lint, typecheck, drift checks, full test, fresh database, generated-file regeneration, and conflict-file globs. Every script here reads it.
2. Pick a scratch directory outside the repo for the integration worktree, logs and the keys file (`$SCRATCH`).
3. If the work needs live API keys, the user puts them in `$SCRATCH/app-keys.env` (mode 600) or in environment secrets. Never ask for them in chat. Loading them is covered in `references/live-verification.md`.

# The loop

## Step 1: Map the backlog to owners

- List the open issues and their epics.
- For each epic, read the issue bodies and the repo's status ledger (create one if missing, see `references/issue-hygiene.md`). Separate **buildable** work from work **blocked on outside resources**.
- Assign one owner per epic, or per cluster of issues that touch the same files. Two owners editing the same module is the most expensive conflict. When it can't be avoided, tell each owner about the other (Step 2).
- Cap concurrency at what the machine can test: about 4–6 owners on a 4-CPU box. Load average drives the timing flakes in Step 4.

## Step 2: Brief each owner

Start each owner in an isolated worktree, in the background, with the brief from `references/owner-brief.md`. Every brief names:

- **the exact base SHA** to reset to, which is your integration branch, not main, when it carries unmerged work;
- **its own database** (the shared one bloats until timing tests fail);
- **the decisions you've already made**, so the owner doesn't re-litigate them;
- **overlaps** with other owners and which version wins;
- **a spend cap, a deadline and a cleanup scope** for any live resource;
- **"done means"**: the full lint output read, types, the tests of touched packages, docs and status rows updated, and a secret scan of each staged diff;
- **"commit, don't push; report SHAs".**

Most bad hand-backs trace to a missing line in the brief.

## Step 3: Integrate hand-backs

```bash
scripts/integrate.sh <integration-worktree> <side-name> <sha-or-range>...
```

- **Work in a side worktree** of the integration branch, so a full test run in the main integration worktree keeps going.
- **Conflicts:** `scripts/merge_loop.sh` continues the cherry-pick. It resolves append-only indexes with `union.py` and status tables row by row with `merge_rows.py`, and stops on anything else or on a row both sides changed.
- **Generated files** (bundles, lockfiles, codegen, OpenAPI exports) are never hand-merged. Take either side and regenerate with the project's generator.
- **Overlapping fixes:** when two owners fixed the same bug, keep one fix, not two. Send the later owner back to rebase (`references/integration.md`).

## Step 4: Gate

```bash
scripts/gate.sh <worktree>      # lint → typecheck → drift → pins → full suite on a fresh DB
scripts/keyscan.sh <base>       # added lines only; exits 1 on anything secret-shaped
```

Rules that cost a red main when skipped are in `references/gate.md`:

- **Read the whole lint log**, not its last line.
- **Run the full suite on a fresh database.**
- **If your machine runs as root and CI doesn't,** run permission-sensitive tests through `scripts/as-user.sh`.
- **A failure is "known flaky" only after it passes alone.** Even then, find the timing cause: fixed sleeps, animations, load.
- **Check every scan match by hand.** A placeholder like `sk-ant-...` in fixture data is fine; anything real stops the push.

## Step 5: Push, PR, shepherd

- **Push:** push the integration branch as a fast-forward. Never force-push without the user's explicit permission.
- **Open the PR** with the body template from `references/pr-lifecycle.md`. It lists what landed, the checks, `Closes #…` for the code-complete issues, and what's left for outside resources.
- **Subscribe to PR activity** and keep one safety-net check-in.
- **Review-bot findings are claims.** Reproduce each real one, fix it with a test, and push. Decline the rest in a single PR comment and resolve their threads.
- **Before any push to an open PR, check it hasn't merged.** Owners of fast-moving repos merge before CI finishes. Commits pushed after a merge need a follow-up PR, and `Closes` lines edited after a merge close nothing.

## Step 6: After merge

1. Check which of your SHAs actually reached main (`git merge-base --is-ancestor`).
2. Comment on the closed issues: what landed, and where each remaining live item is tracked.
3. Close an epic once all its sub-issues are closed.
4. Watch main's CI on the merge commit. A PR merged before its own CI finished gets its first full run here.
5. Reset the integration branch to `origin/main` by fast-forward, and fast-forward the main checkout.
6. Remove finished owners' worktrees. Kill leaked temp directories at the source (`references/gate.md`).

## Step 7: Live verification (when keys exist)

Run live checks early. Fakes hide the bugs that matter: spend caps compared against the wrong field, response shapes, buffer limits, missing identities. Follow `references/live-verification.md`:

- **Keys:** loaded from a mode-600 file and never echoed.
- **Spend:** capped per owner.
- **Resources:** every created resource recorded and deleted.
- **Results:** recorded in a dated doc with a spend table.
- **Fakes:** corrected to the live shapes.

**Account-wide or billing changes need the user's explicit yes, in their words.** If the runtime's safety check refuses an action, ask the user. Never route it through a sub-agent.

# Rules

- **Only the integrator pushes, opens PRs and closes issues.** Owners commit in their worktrees.
- **Close an issue when its code is complete.** Its live checks move to a tracker issue grouped by resource (test org, datasets, third-party accounts). The backlog stays honest, and nothing is closed with buildable work left.
- **Never** skip, disable or quarantine a test to get green. Never push an empty commit to re-run CI.
- **Secrets live in a mode-600 file or environment secrets, never in chat, commits, logs or command lines.** `/proc/<pid>/cmdline` is world-readable; pass env through the environment.
- **Record deadlines in a file, not in memory.** Key expiry, trial ends and rate-limit windows go in the plan, with a scheduled checkpoint.

# Known gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Lint "passed" locally, CI red | Only the last line of output was read | `gate.sh` keeps the full log; read it all |
| Tests pass here, `EACCES` in CI | The container runs as root | `scripts/as-user.sh` for permission-sensitive tests |
| DB-backed tests time out after a few hours | Every owner wrote to one shared dev DB | A fresh DB per full run (`FRESH_DB_CMD`) and one DB per owner |
| `|||||||` lines committed | A union resolver didn't understand diff3 markers | `union.py` handles diff3; `merge_loop.sh` refuses to continue with markers left |
| Duplicate rows in the status table | One branch moved a row, the other edited it | `merge_rows.py` exits 1 on duplicate keys; resolve by hand |
| Typecheck fails right after integration | Generated types (env, codegen) are stale | Regenerate (`REGEN_CMD`), the same as CI's install step |
| Late commits missing from main | The PR merged before the last push | Check merge state before pushing; open a follow-up PR |
| `Closes #N` didn't close | The PR body was edited after the merge | Close by hand with a comment, or use a follow-up PR |
| A UI target measures 43 px, not 44 | The audit ran mid-animation under load | Wait for finite animations before measuring |
| `ENOBUFS` reading a large file | A default 1 MiB exec buffer | Size the buffer to the file; refuse over the API limit |
| A spend cap never trips | The vendor's "dollars" field was a fee, not usage | Price the tokens yourself; verify the cap live |
| The disk fills mid-day | Finished worktrees and leaked test temp dirs | Remove finished worktrees; point the test runner's `TMPDIR` at one per-run directory |
| A force-push or billing change was refused | The runtime's safety check | Use fast-forward or a follow-up PR; ask the user for billing changes |

# References

| File | Load when |
|---|---|
| `references/owner-brief.md` | Writing an owner's brief (Step 2) |
| `references/integration.md` | Cherry-picking, conflicts, overlapping fixes (Step 3) |
| `references/gate.md` | Before every push (Step 4) |
| `references/pr-lifecycle.md` | Opening, shepherding and closing out a PR (Steps 5–6) |
| `references/issue-hygiene.md` | The status ledger, trackers, closing issues and epics |
| `references/live-verification.md` | Any run with real keys or paid resources (Step 7) |
