<!-- Banner pending OPENROUTER_API_KEY: bash skills/terminal-poster/scripts/generate.sh skills/ephemeral-fleet/assets/banner-prompt.txt skills/ephemeral-fleet/assets/banner.jpg -->

# Ephemeral-Fleet

Stands up per-lane sandboxes from your repo's environmentRecipes, pairs each remote runtime via orca serve, dispatches into them like any worker, harvests work off the mortal disk via git push BEFORE teardown, and destroys every sandbox with a verified ledger row. Bypass-flag autonomy only ever inside a box that stops existing.

## Install

```bash
ln -sfn "$(pwd)/skills/ephemeral-fleet" "$HOME/.claude/skills/ephemeral-fleet"
```
Requires Orca + the `orca-per-workspace-env` skill with a doctor-validated recipe and baked agent-auth snapshots.

## Use

"Run the sweep in sandboxes" → N lanes, N sandboxes, danger sanctioned per-lane in the ledger, branches pushed before destroy, teardown verified against the provider. Anything not pushed before DESTROY never happened — the completion contract enforces the order.

## Structure

```
ephemeral-fleet/
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
