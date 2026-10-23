# Playwright patterns

# Full-page screenshot

```ts
import { test, expect } from "@playwright/test";

test("home renders", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => document.fonts.ready);
  await expect(page).toHaveScreenshot("home.png", { fullPage: true });
});
```

# Component-scoped screenshot

Screenshot the component, not the whole page. Smaller images produce fewer false diffs and clearer failures.

```ts
test("pricing card stays stable", async ({ page }) => {
  await page.goto("/pricing");
  const card = page.getByTestId("pricing-card-pro");
  await expect(card).toHaveScreenshot("pricing-card-pro.png", {
    mask: [card.getByTestId("price")],
  });
});
```

# State before capture

```ts
test("security drawer", async ({ page }) => {
  await page.goto("/settings");
  await page.getByTestId("open-security").click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await expect(page).toHaveScreenshot("settings-security.png");
});
```

Wait for the visible state, not a fixed sleep. If you must wait, wait for a specific condition:

```ts
await page.waitForFunction(() => document.fonts.status === "loaded");
await page.waitForLoadState("networkidle");
```

# Reusable fixture

```ts
// tests/visual/fixtures.ts
import { test as base, expect } from "@playwright/test";

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.clock.setFixedTime(new Date("2026-01-01T12:00:00Z"));
    await page.addInitScript(() => {
      Math.random = () => 0.42;
    });
    await use(page);
  },
});

export { expect };
```

# Masking sensitive or volatile regions

```ts
const masks = [
  page.locator("[data-private]"),
  page.getByTestId("avatar"),
  page.getByTestId("last-seen"),
];
await expect(page).toHaveScreenshot("profile.png", { mask: masks, maskColor: "#ff00ff" });
```

Prefer `data-private` / `data-testid` hooks over CSS classes that change with styling.

# Selectors

Use stable hooks:

- `getByTestId("...")`
- `getByRole("button", { name: "Save" })` when the accessible name is stable
- `[data-testid="..."]` in raw selectors
- `[data-private]` for redaction targets

Avoid:

- visible text that changes with copy
- long CSS chains
- `.nth(3)` unless order is part of the contract
- XPath

# Assertions that help triage

```ts
await expect(page.getByRole("heading", { level: 1 })).toHaveText(/pricing/i);
await expect(page).toHaveURL(/\/pricing$/);
await expect(page.getByTestId("plan-grid")).toHaveCount(3);
```

Add semantic assertions beside the screenshot. When the image diff is ambiguous, the semantic assertion tells you whether the page is structurally correct.

# Projects and matrix

```ts
projects: [
  { name: "desktop-light", use: { ...devices["Desktop Chrome"], colorScheme: "light" } },
  { name: "desktop-dark", use: { ...devices["Desktop Chrome"], colorScheme: "dark" } },
  { name: "mobile-light", use: { ...devices["iPhone 13"], colorScheme: "light" } },
];
```

Keep `deviceScaleFactor: 1` unless HiDPI rendering is under test. Use `devices` only after confirming the scale factor and user agent are stable in CI.

# Snapshot naming

Use one snapshot per route × viewport × state:

```
home-desktop-light.png
home-mobile-light.png
settings-security-open-desktop-dark.png
```

A stable naming scheme makes it possible to find, review, and delete baselines without guessing.

# Test isolation

- Reset storage between tests unless the auth fixture intentionally shares it.
- Seed the database or mock the API per test.
- Do not depend on another test's side effects.
- Run visual tests in parallel only when the app and data are isolated.

# Debugging

```bash
npx playwright test tests/visual --debug
npx playwright show-trace test-results/*/trace.zip
npx playwright test tests/visual --update-snapshots   # local only, review every image
```

On failure, read the expected/actual/diff images before reading the stack trace. The images usually identify the cause faster.
