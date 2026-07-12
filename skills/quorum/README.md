<!-- Banner pending OPENROUTER_API_KEY: bash skills/terminal-poster/scripts/generate.sh skills/quorum/assets/banner-prompt.txt skills/quorum/assets/banner.jpg -->

# Quorum

Broadcast a self-contained ballot to @claude / @codex / @idle on a shared thread, reduce the replies to an auditable consensus table, and route splits to gate-steward as taste gates. JURY mode runs full independent candidates first (the quorum pattern), with jurors never judging their own work.

## Install

```bash
ln -sfn "$(pwd)/skills/quorum" "$HOME/.claude/skills/quorum"
```
Requires Orca (runtime + `orchestration` CLI skill); multiple agent CLIs for cross-model votes.

## Use

"Is this clean-sweep finding real?" → VOTE mode with refute framing, majority-of-cast quorum, denominator honesty (2-of-7-voted is not 2-of-2). "Implement it three ways and pick" → JURY mode. Unanimous VOTE may act; splits become taste gates; **JURY winner pick is always human-gated** (even if unanimous). Nothing gets averaged into a 2.5.

## Structure

```
quorum/
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
