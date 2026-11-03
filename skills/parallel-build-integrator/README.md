# parallel-build-integrator

Turn a big GitHub backlog into merged, green PRs. One owner agent per epic writes code in parallel worktrees, and one integrator brings their work together on one branch. The integrator gates every push, shepherds the PR through CI and review bots, and closes issues once their code is complete. Live checks that need outside accounts move to tracker issues.

It comes from a single session that took a 133-issue product backlog to 3 open tracker issues in a day:
- 14 epics closed;
- about 20 integration PRs;
- live runs against real model and sandbox APIs, each capped and cleaned up.

Every rule and script here exists because skipping it once cost a red main, a lost commit or a leaked secret.

## When to use

Say things like:
- "build everything end to end, autonomously"
- "run agents in parallel, one per epic"
- "don't ask me — review the PRs and merge them yourself"
- "integrate the agents' work and keep refreshing against main"
- "close the completed issues; track what needs outside resources"

For driving one half-built product to launch-readiness with a frozen definition of done, use [`finish-line`](../finish-line/).

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
ln -s "$(pwd)/agent-skills/skills/parallel-build-integrator" ~/.claude/skills/parallel-build-integrator
```

In the project you'll build:

```bash
mkdir -p .integrator
cp ~/.claude/skills/parallel-build-integrator/templates/config.sh .integrator/config.sh
# edit: your lint, typecheck, drift, fresh-DB and test commands, and the conflict-file globs
```

**Requirements:**
- `git` (worktrees), `bash` and `python3`;
- an agent runtime that can start sub-agents in isolated worktrees (Claude Code's Agent tool);
- GitHub access through `gh` or a GitHub MCP server.

**Optional:** `runuser`, for non-root test runs; a local database server, for a fresh test DB per run.

## Usage

The agent follows `SKILL.md`. The scripts work on their own too:

```bash
S=~/.claude/skills/parallel-build-integrator/scripts

# Integrate an owner's commits in a side worktree of the integration branch
$S/integrate.sh "$SCRATCH/integ" cli 359bb84^..85bd168

# Pre-push gate: regenerate → lint → typecheck → drift → full suite on a fresh DB
$S/gate.sh "$SCRATCH/integ-cli"

# Secret-shaped strings in the added lines
$S/keyscan.sh origin/main "$SCRATCH/integ-cli"

# Permission-sensitive tests as CI's non-root user, environment kept off the command line
$S/as-user.sh nobody pnpm exec vitest run apps/cli/src/sea-prelude.test.ts

# Resolve conflicts by hand
$S/union.py docs/adr/README.md          # append-only: keep both sides
$S/merge_rows.py docs/plan/status.md    # keyed table: per row, the side that changed
```

**Cost:** agent compute only. Live verification spends what its caps allow, with every resource recorded and deleted.

## Files

```
SKILL.md                     the integrator's loop (agent-facing)
references/owner-brief.md    the brief template every owner gets
references/integration.md    branch layout, cherry-pick order, conflict classes
references/gate.md           the pre-push gate, failure classification, root vs CI
references/pr-lifecycle.md   PR body, shepherding, after-merge checklist
references/issue-hygiene.md  status ledger, trackers, closing issues and epics
references/live-verification.md  keys, spend caps, approvals, cleanup, records
scripts/                     integrate, merge_loop, union, merge_rows, gate, keyscan, as-user
templates/config.sh          per-project commands and conflict globs
```

## Known gotchas

See the table in [`SKILL.md`](SKILL.md#known-gotchas). The costliest ones:
- **Only the last line of lint output was read**, and main went red.
- **Tests passed as root**, then failed in CI with `EACCES`.
- **A PR merged before its last push**, so the late commits needed a follow-up PR.
- **A spend cap was compared against the vendor's fee field**, not usage, so it would never have tripped.

## Credits

Distilled from one Claude Code session that built a production product's whole backlog end to end.
