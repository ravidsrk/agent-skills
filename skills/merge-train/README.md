<!-- Banner pending OPENROUTER_API_KEY: bash skills/terminal-poster/scripts/generate.sh skills/merge-train/assets/banner-prompt.txt skills/merge-train/assets/banner.jpg -->

# Merge-Train

Workers signal merge_ready with PR + the SHA their reviewer actually approved; ONE conductor merges strictly in arrival order, bouncing stale evidence back to the owning review fleet, rebasing as a union with --force-with-lease only, and verifying every merge on the base before believing it.

## Install

```bash
ln -sfn "$(pwd)/skills/merge-train" "$HOME/.claude/skills/merge-train"
```
Requires Orca (runtime + `orchestration` CLI skill), git + gh, an integration BASE branch.

## Use

"My parallel PRs keep racing each other onto the integration branch" → one conductor terminal owns the queue. Merge-to-default stays a human gate (gate-steward, one-way) — the train serves the integration BASE only. Conductor crash? run-supervision rebuilds the queue from persisted merge_ready messages.

## Structure

```
merge-train/
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
