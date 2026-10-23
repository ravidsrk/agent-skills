# visual-regression

Catch unintended UI changes with screenshot baselines, perceptual diffs, and CI gates.

## What it does

- Captures deterministic screenshots across routes, viewports, themes, and states.
- Compares them against reviewed baselines and reports expected/actual/diff images.
- Redacts sensitive regions before capture.
- Triages perceptual clusters so one CSS cause is fixed once.
- Verifies the fix with a passing screenshot and attaches evidence to the PR.
- Runs as a CI gate with artifacts on failure.

Plain Playwright is enough. [Frontguard](https://github.com/ravidsrk/frontguard) is optional for perceptual clustering, an orphan-branch baseline store, and an MCP loop that lets an agent list, inspect, patch, and verify regressions.

## When to use

- "Add visual regression tests" / "screenshot diff" / "pixel diff"
- "Did this CSS change break anything?"
- "Verify the UI change" / "show me before and after"
- "Update the visual baselines"
- Frontend refactors, design-system upgrades, dependency bumps, theme changes

## Install

```bash
npm i -D @playwright/test
npx playwright install --with-deps chromium
export APP_URL="http://localhost:3000"
```

Optional Frontguard backend:

```bash
npm i -D @frontguard/cli @frontguard/playwright
npx @frontguard/cli doctor
```

## Quick start

Scaffold a minimal setup:

```bash
bash scripts/scaffold.sh --dir . --url "$APP_URL"
npx playwright test tests/visual --update-snapshots   # review every image, then commit
npx playwright test tests/visual                      # regression run
```

Run with Frontguard instead:

```bash
npx @frontguard/cli init --yes
npx @frontguard/cli update-baselines --url "$APP_URL"
npx @frontguard/cli run --url "$APP_URL" --wait-for-stability --redact-sensitive
```

## What a failure gives you

- `expected.png` — the reviewed baseline
- `actual.png` — the current render
- `diff.png` — the changed pixels
- A DOM snapshot or cluster report when using Frontguard

Use the diff image to classify the change before touching the baseline.

## CI

```yaml
- run: npx playwright test tests/visual
- uses: actions/upload-artifact@v4
  if: failure()
  with:
    name: visual-diffs
    path: test-results/
```

Never run `--update-snapshots` in CI. A new snapshot is a failure until a human reviews it.

See [`references/ci.md`](references/ci.md) for baseline storage options and a complete workflow.

## File layout

```
visual-regression/
├── SKILL.md
├── README.md
├── references/
│   ├── setup.md
│   ├── diffing.md
│   ├── playwright.md
│   ├── ci.md
│   └── evidence.md
└── scripts/
    └── scaffold.sh
```

## Known gotchas

| Gotcha | Fix |
|---|---|
| Fonts render differently on every machine | Pin the browser and OS; wait for `document.fonts.ready`; run in the same container as CI |
| Animations cause false diffs | Disable transitions/animations; wait for a stable frame |
| Timestamps/avatars/tokens change every run | Freeze time; mask volatile elements |
| Dark mode screenshots drift | Pin `colorScheme` per project |
| Mobile layout differs | Pin viewport and `deviceScaleFactor` |
| New screenshot silently accepted | Fail on new snapshots; review baselines in PRs |
| Agent promotes a broken baseline | Require an independent verifier or human approval before promotion |

## Pairs with

- [`references/evidence.md`](references/evidence.md) — screenshots/video for async review.
- `finish-line` — visual verification during launch-readiness runs.

## Credits

- Workflow and reference material adapted from [Frontguard](https://github.com/ravidsrk/frontguard) (MIT, Copyright (c) 2026 Ravindra Kumar).
- Evidence capture contract adapted from [background-agents](https://github.com/Open-Inspect/background-agents) (MIT, Copyright (c) 2024 Open-Inspect Contributors).

## License

MIT
