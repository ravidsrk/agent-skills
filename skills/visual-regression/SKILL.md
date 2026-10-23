---
name: visual-regression
description: >-
  Detect unintended UI changes by comparing Playwright screenshots against reviewed
  baselines — stabilize renders, redact sensitive DOM, cluster perceptual diffs, verify
  fixes, and gate CI. Use when the user asks for visual regression tests, screenshot
  diffs, baseline updates, UI change verification, responsive layout checks, or "did
  this CSS change break anything?"
license: MIT
compatibility: Requires Node.js 20+, Playwright, and a reachable app URL. Optional Frontguard CLI/MCP for perceptual clustering and agent-driven verification.
metadata:
  version: "0.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Visual Regression

Catch visual regressions the way tests catch logic regressions: capture stable screenshots, compare them against reviewed baselines, and make the diff the gate. This skill covers the whole loop — deterministic capture, sensitive-data redaction, perceptual triage, fix verification, baseline promotion, CI, and agent-readable evidence.

It works with plain `@playwright/test`. Frontguard is an optional backend for perceptual clustering, orphan-branch baselines, and an MCP loop for agents.

# When to use

Trigger on any of:

- "Add visual regression tests" / "screenshot diff" / "pixel diff"
- "Did this CSS change break anything?"
- "Verify the UI change" / "show me before and after"
- "Update the visual baselines"
- "Check responsive layouts" / "test this at mobile and desktop"
- A frontend refactor, design-system upgrade, dependency bump, or theme change
- Before merging a PR that changes layout, spacing, typography, color, or components

# When NOT to use

- A brand-new page with no reviewed baseline yet — capture a baseline first, then treat later runs as regression checks.
- Purely semantic changes with no visual surface.
- The app cannot render deterministically (live data, third-party embeds, random content). Mock or freeze those inputs first.
- The user wants exploratory screenshots for a review, not a pass/fail gate — use the evidence workflow in `references/evidence.md`.

# Setup

Minimum:

```bash
npm i -D @playwright/test
npx playwright install --with-deps chromium
export APP_URL="http://localhost:3000"
```

Optional, for perceptual clustering and an agent MCP loop:

```bash
npx @frontguard/cli doctor
npx @frontguard/cli init --yes
```

Scaffold a starting point:

```bash
bash scripts/scaffold.sh --dir . --url "$APP_URL"
```

The scaffold writes `playwright.config.ts` and `tests/visual/home.spec.ts`. It refuses to overwrite existing files unless `--force` is passed.

# The workflow

## Step 1 — Inventory what to capture

List routes × viewports × states. Capture only surfaces a user can see.

| Dimension | Start with |
|---|---|
| Routes | `/`, `/pricing`, `/login`, the page the PR changes |
| Viewports | 375×812, 768×1024, 1440×900 |
| States | default, hover/focus, open menu, empty, error, loading |
| Themes | light and dark if both ship |

Keep the matrix small. Ten meaningful screenshots reviewed every PR beat two hundred ignored ones.

## Step 2 — Make the render deterministic

Before the first capture, remove sources of false diffs:

- Wait for `document.fonts.ready` and network idle.
- Disable animations and transitions, or set them to a fixed end state.
- Freeze clocks, random values, and relative timestamps.
- Mock third-party widgets, maps, ads, and live data.
- Wait for images to decode and lazy content to settle.
- Hide or redact volatile regions (avatars, emails, tokens, order IDs).

```ts
await page.goto(url, { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.addStyleTag({
  content: `*, *::before, *::after { animation: none !important; transition: none !important; }`,
});
```

## Step 3 — Capture baselines

```bash
npx playwright test tests/visual --update-snapshots
```

Review every new baseline image before committing it. A baseline is a test expectation: committing a broken screenshot makes the bug permanent.

Store baselines in git (small apps) or a dedicated orphan branch (`visual-baselines`) for large matrices. See `references/ci.md`.

## Step 4 — Run the comparison

```bash
npx playwright test tests/visual
```

Playwright writes expected/actual/diff images on failure. For perceptual clustering and a machine-readable report:

```bash
npx @frontguard/cli run --url "$APP_URL" --wait-for-stability --redact-sensitive
```

Exit codes: `0` = pass, `1` = visual diff or new snapshot, `2` = configuration/runtime error. Treat `2` as a broken test, not a regression.

## Step 5 — Triage before touching the baseline

For each diff:

1. Open the diff image, not just the percentage.
2. Classify: intended design change, unintended regression, environment noise, or test bug.
3. Inspect the DOM around the changed region (`[data-testid]`, computed styles, box model).
4. Cluster diffs that share a cause; fix the cause once.
5. Re-run the affected screenshots only.

Never promote a baseline to make red turn green. Promote only after a human or an independent verifier accepts the new appearance.

## Step 6 — Fix and verify

```bash
# After the CSS/component fix
npx playwright test tests/visual
```

Required evidence before claiming the fix works:

- The previously failing screenshot now passes.
- The diff image is empty or below the agreed threshold.
- A screenshot or short video of the fixed state is attached to the PR/issue.

## Step 7 — Gate CI

Run the suite on every PR, upload expected/actual/diff artifacts on failure, and block merge on a diff. See `references/ci.md` for a complete GitHub Actions job.

## Step 8 — Agent loop (optional)

If the agent has Frontguard MCP tools:

```text
list_regressions
  → inspect_diff_cluster_dom
  → verify_css_patch
  → promote_baseline
```

The loop is: enumerate regressions, inspect the cluster and its DOM, patch the smallest cause, re-verify the same cluster, then promote only the accepted baseline. Without MCP, use the CLI plus the same order.

# Evidence artifacts

Screenshots prove a state; videos prove an interaction. For both:

- Set the viewport explicitly and report it.
- Capture full-page only when the whole document matters.
- Use a stable selector, not visible text, for interactions.
- Probe encoded video dimensions/duration with `ffprobe`; do not report the requested viewport as the video size.
- Attach the artifact and a one-line statement of what was verified.

See `references/evidence.md` for the capture and upload contract.

# Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Every screenshot differs by a few pixels | Fonts or anti-aliasing differ between machines | Run in the same container/browser version; wait for `document.fonts.ready`; use a perceptual threshold |
| Diff only on the first run | Animations, lazy images, or network still settling | Disable animations; wait for stability; mock slow requests |
| Diff contains a timestamp, avatar, or token | Volatile or sensitive content | Freeze time; redact with a stable mask |
| Dark mode changes every screenshot | Color scheme not pinned | Set `colorScheme` per project or per test |
| Mobile layout differs wildly | Device scale factor or viewport not pinned | Pin viewport and `deviceScaleFactor` |
| Huge diff after a dependency bump | Browser version changed rendering | Re-baseline in the pinned CI image and review the diff |
| Test passes locally, fails in CI | Different OS/font stack | Run visual tests in the same container locally and in CI |
| New snapshot silently accepted | `--update-snapshots` in CI | Never run update mode in CI; fail on new snapshots |

# References

- `references/setup.md` — install, config, auth state, route inventory
- `references/diffing.md` — thresholds, perceptual metrics, stability, redaction
- `references/playwright.md` — component-scoped assertions, fixtures, selectors
- `references/ci.md` — GitHub Actions, baseline storage, artifacts
- `references/evidence.md` — screenshot/video evidence and upload
- `scripts/scaffold.sh` — generate a minimal Playwright visual setup
