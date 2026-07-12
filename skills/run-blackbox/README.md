<!-- Banner pending OPENROUTER_API_KEY: bash skills/terminal-poster/scripts/generate.sh skills/run-blackbox/assets/banner-prompt.txt skills/run-blackbox/assets/banner.jpg -->

# Run-Blackbox

Every worker_done (filesModified, reportPath), heartbeat phase, and dispatch context survives coordinator death in the runtime's SQLite store. This skill reads it back: STATUS is the missing run dashboard, RESUME reconstructs a crashed run (cross-verified against git) and re-enters the loop, AUDIT writes the post-run report.

## Install

```bash
ln -sfn "$(pwd)/skills/run-blackbox" "$HOME/.claude/skills/run-blackbox"
```
Requires Orca (runtime + `orchestration` CLI skill), git, gh for PR cross-checks.

## Use

"Where is the run?" → STATUS. "The coordinator died overnight" → RESUME (freeze-check first, provenance rebuilt, ledger reconciled, loop re-entered). "What did last week's run actually do?" → AUDIT to `docs/audits/`. Never uses `check --unread` (won't steal a live coordinator's messages).

## Structure

```
run-blackbox/
├── SKILL.md          # the agent-facing playbook — read top to bottom
├── README.md
├── scripts/          # spawn_worker (calls Orca) · preflight (git/gh) · pm (JSON parser)
├── assets/           # banner + reproducer prompt
└── references/       # ledger template
```

The `scripts/` helpers are GENERATED from this repo's `scripts/orca-coord/` — edit the
canonical files and run `python3 scripts/sync-orca-coord.py`, never the copies.

## License

MIT
