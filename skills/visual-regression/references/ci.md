# CI

# Goals

- Run the same browser and OS locally and in CI.
- Fail the pull request on a visual diff or a new snapshot.
- Upload expected/actual/diff images so a reviewer can inspect the failure.
- Keep baselines reviewable and out of the main tree when the matrix is large.

# GitHub Actions

```yaml
name: visual-regression

on:
  pull_request:
  push:
    branches: [main]

jobs:
  visual:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci
      - run: npx playwright install --with-deps chromium

      - name: Start app
        run: |
          npm run build
          npm run start &
          npx wait-on "$APP_URL" --timeout 60000
        env:
          APP_URL: http://localhost:3000

      - name: Visual tests
        run: npx playwright test tests/visual
        env:
          APP_URL: http://localhost:3000
          CI: true

      - name: Upload diffs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: visual-diffs
          path: |
            test-results/
            playwright-report/
          retention-days: 7
```

# Pin the environment

Visual output depends on the browser build, fonts, and OS. Pin all three:

- `npx playwright install --with-deps chromium` in a known container image
- a browser version pinned by the Playwright version in `package-lock.json`
- fonts installed explicitly in CI (or self-hosted in the app)

If local and CI use different environments, run the suite in Docker locally:

```bash
docker run --rm -v "$PWD:/work" -w /work mcr.microsoft.com/playwright:v1.50.0-jammy \
  npx playwright test tests/visual
```

# Baseline storage

## Option A — in the repository

```
tests/visual/__screenshots__/
  home-desktop-light.png
  pricing-mobile-light.png
```

Simple, reviewable in the PR, works for small matrices. Can bloat the repo for large apps.

## Option B — orphan branch

```bash
git checkout --orphan visual-baselines
git rm -rf .
# add baselines, commit, push
git checkout main
```

Configure the test to read/write from a checkout of that branch:

```bash
git worktree add .visual-baselines visual-baselines
BASELINE_DIR=.visual-baselines npx playwright test tests/visual
```

This keeps screenshots out of the main history while preserving reviewability. Frontguard does this automatically with its `frontguard-baselines` branch.

## Option C — artifact store

Upload baselines to object storage keyed by branch/commit. More moving parts; use only when the matrix is too large for git and you need cross-repo sharing.

# New snapshots are failures

Playwright creates a missing snapshot and fails by default. Keep that behavior:

```ts
// Do not set updateSnapshots: "all" in CI.
expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.002 } }
```

A new snapshot means a new surface with no reviewed expectation. A human must approve the image before it becomes a baseline.

# PR feedback

Post a short comment with the artifact link and the count of diffs. Avoid pasting images into the PR body; link the artifact instead.

```yaml
- name: Comment on failure
  if: failure() && github.event_name == 'pull_request'
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        ...context.repo,
        issue_number: context.issue.number,
        body: `Visual regression failed. Download the diff artifacts from this workflow run.`,
      });
```

# Caching

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/ms-playwright
    key: playwright-${{ runner.os }}-${{ hashFiles('package-lock.json') }}
```

Do not cache `test-results/` or baselines from a previous run.

# Required check

Mark the visual job as a required status check for `main`. A visual diff that does not block merge is documentation, not a gate.

# Agent-friendly output

Write a machine-readable summary on failure:

```json
{
  "total": 24,
  "failed": 2,
  "new": 0,
  "diffPercentage": { "home-desktop-light": 0.004, "pricing-mobile-light": 0.012 },
  "artifacts": ["test-results/.../diff.png"]
}
```

This lets an agent triage clusters and decide whether to inspect the DOM, fix CSS, or ask for a baseline review.
