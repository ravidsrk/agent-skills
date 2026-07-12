<img src="assets/banner.jpg" alt="Standing-Fleet — Scheduled coordinator runs on `orca automations`" width="100%">

# Standing-Fleet

Turns any one-shot fleet in this pack into a standing, scheduled autonomous run: cron/RRULE triggers, a precheck that skips empty runs for free, parked human gates between runs, and a per-automation ledger as cross-run memory.

## Install

```bash
ln -sfn "$(pwd)/skills/standing-fleet" "$HOME/.claude/skills/standing-fleet"
```
Requires Orca (runtime + `orchestration` CLI skill + `orca automations`), plus the fleet skill you schedule and ITS dependencies.

## Use

Ask your agent: "schedule ready-agent-drain nightly at 02:30, skip when the queue is empty" — the skill confirms cadence + budget, writes the precheck, creates the automation with the standing-run prompt, and shows you `orca automations runs` for history. Parked one-way gates wait in `docs/standing/<name>.md` for you (or gate-steward) between runs.

## Structure

```
standing-fleet/
├── SKILL.md          # the agent-facing playbook — read top to bottom
├── README.md
├── scripts/          # spawn_worker (calls Orca) · preflight (git/gh) · pm (JSON parser)
├── assets/           # standing-run prompt template + banner
└── references/       # ledger template
```

The `scripts/` helpers are GENERATED from this repo's `scripts/orca-coord/` — edit the
canonical files and run `python3 scripts/sync-orca-coord.py`, never the copies.

## License

MIT
