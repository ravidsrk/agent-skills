<img src="assets/banner.jpg" alt="Test-Debt-Zero — Autonomous mission: every critical path has a mutation-audited test" width="100%">

# Test-Debt-Zero

Map the untested critical surface (coverage × call-graph of the money/auth/data paths), write characterization tests that assert real behavior, prove each one earns its keep by failing at its assertion under a semantics-preserving MUTATION of its code (a compile break doesn't count — the harness must stay runnable), and route surfaced bugs to a fix or backlog — looping until every confirmed critical path is mutation-audited. Coverage percent is a proxy; the mutation-audit is the truth.

## Install

```bash
ln -sfn "$(pwd)/skills/test-debt-zero" "$HOME/.claude/skills/test-debt-zero"
```
Requires Orca + `orchestration`, git + gh, a runnable suite + coverage tool, and a TDD playbook (addyosmani or mattpocock — one router per worker).

## Use

"Close the test gap on the payments and auth paths." → map the critical surface (human-confirmed to bound it), characterize with real assertions, mutation-audit each test (it must fail at its assertion under a semantics-preserving code mutation, harness still runnable), and hand surfaced bugs to clean-sweep. A test insensitive to the behavior is worthless and the mission knows it.

## Structure

```
test-debt-zero/
├── SKILL.md          # the mission playbook — read top to bottom
├── README.md
├── scripts/          # spawn_worker (calls Orca) · preflight (git/gh) · pm (JSON parser)
├── assets/           # banner + reproducer prompt
└── references/       # ledger template
```

The `scripts/` helpers are GENERATED from this repo's `scripts/orca-coord/` — edit the
canonical files and run `python3 scripts/sync-orca-coord.py`, never the copies.

## License

MIT
