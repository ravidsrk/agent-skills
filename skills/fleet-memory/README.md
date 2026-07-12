<img src="assets/banner.jpg" alt="Fleet-Memory — Compounding learnings + adaptive review gating across runs" width="100%">

# Fleet-Memory

Append-only per-repo learnings JSONL written at REFLECT phases, injected (cap 5, visible, verbatim) into future dispatch preambles, pruned on staleness and contradiction, plus specialist hit-rate stats that gate off reviewers with zero findings in ten dispatches — security and data-migration never gated. Adapted from gstack's learnings/retro loop.

## Install

```bash
ln -sfn "$(pwd)/skills/fleet-memory" "$HOME/.claude/skills/fleet-memory"
```
Requires Orca (runtime + `orchestration` CLI skill); python3; a repo for the committed store.

## Use

"Why does every run rediscover the worktree-selector gotcha?" → write it once at REFLECT, and run N+1's workers get "PRIOR LEARNINGS: [worktree-selector-composite-id] ..." in their TASK. Workers echo applied keys in worker_done so retro-cron can show the compounding.

## Structure

```
fleet-memory/
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
