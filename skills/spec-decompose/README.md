<!-- Banner pending OPENROUTER_API_KEY: bash skills/terminal-poster/scripts/generate.sh skills/spec-decompose/assets/banner-prompt.txt skills/spec-decompose/assets/banner.jpg -->

# Spec-Decompose

The runtime's `orchestration run` requires pre-created tasks and does no decomposition. This skill cuts a frozen spec into vertical slices sized one-context-window each, materializes them as `task-create --deps` in topological order, verifies the DAG (cycles, frontier, hot-file chains), and launches either the runtime coordinator with auto-provisioning or a manual wave loop.

## Install

```bash
ln -sfn "$(pwd)/skills/spec-decompose" "$HOME/.claude/skills/spec-decompose"
```
Requires Orca (runtime + `orchestration` CLI skill) and a frozen, human-gated spec.

## Use

"Decompose this spec and run it, max 4 workers" → slices, DAG, `orchestration run --worktree --max-concurrent 4`, with run-supervision watching stalls and run-supervision as the dashboard. The base-drift skip (>20 commits behind, silent) and the one-active-run limit are called out so they don't cost you an afternoon.

## Structure

```
spec-decompose/
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
