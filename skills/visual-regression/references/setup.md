# Setup

# Prerequisites

- Node.js 20+
- `@playwright/test`
- A running app (local dev server or preview URL)
- Optional: `@frontguard/cli` and `@frontguard/mcp`

# Install

```bash
npm i -D @playwright/test
npx playwright install --with-deps chromium
```

# Minimal `playwright.config.ts`

```ts
import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.APP_URL ?? "http://localhost:3000";

export default defineConfig({
  testDir: "./tests/visual",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.002,
      animations: "disabled",
      caret: "hide",
      scale: "css",
    },
  },
  use: {
    baseURL,
    colorScheme: "light",
    deviceScaleFactor: 1,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "tablet", use: { ...devices["Desktop Chrome"], viewport: { width: 768, height: 1024 } } },
    { name: "mobile", use: { ...devices["Desktop Chrome"], viewport: { width: 375, height: 812 } } },
  ],
});
```

Start the app in CI or locally before the tests. If the app is remote, set `APP_URL` and skip the web server.

# Auth state

Do not log in on every screenshot. Create a storage state once:

```ts
// tests/visual/auth.setup.ts
import { test as setup } from "@playwright/test";

setup("authenticate", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill(process.env.TEST_USER!);
  await page.getByLabel("Password").fill(process.env.TEST_PASSWORD!);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL("/dashboard");
  await page.context().storageState({ path: "tests/visual/.auth/user.json" });
});
```

```ts
// playwright.config.ts
projects: [
  { name: "setup", testMatch: /auth\.setup\.ts/ },
  {
    name: "authenticated",
    use: { storageState: "tests/visual/.auth/user.json" },
    dependencies: ["setup"],
  },
];
```

Add `.auth/` to `.gitignore`. Never commit credentials or storage state.

# Viewports and themes

Use a small matrix:

| Project | Viewport | Theme |
|---|---|---|
| desktop-light | 1440×900 | light |
| desktop-dark | 1440×900 | dark |
| mobile-light | 375×812 | light |

Pin `deviceScaleFactor: 1` unless you are explicitly testing HiDPI rendering. Mixing scale factors creates diffs that are not regressions.

# Route inventory

Write the inventory down before capturing:

```ts
export const routes = [
  { path: "/", name: "home" },
  { path: "/pricing", name: "pricing" },
  { path: "/login", name: "login", anonymous: true },
  { path: "/settings", name: "settings", state: "open-security-drawer" },
];
```

For each route, record:

- whether it needs auth
- which state to open before capture
- which regions are volatile and must be masked
- whether the whole page or only the viewport matters

# Freeze volatile inputs

Set the clock, random seed, and locale in a fixture:

```ts
await page.clock.setFixedTime(new Date("2026-01-01T12:00:00Z"));
await page.addInitScript(() => {
  Math.random = () => 0.42;
});
```

Mock third-party widgets and live data at the network layer with `page.route()`.

# Optional Frontguard backend

```bash
npx @frontguard/cli doctor
npx @frontguard/cli init --yes
npx @frontguard/cli update-baselines --url "$APP_URL"
npx @frontguard/cli run --url "$APP_URL" --wait-for-stability --redact-sensitive
```

Frontguard stores baselines on a `frontguard-baselines` orphan branch by default, so screenshots do not bloat the main tree. Its MCP server exposes `list_regressions`, `inspect_diff_cluster_dom`, `verify_css_patch`, and `promote_baseline` for agent loops.

# Checklist

- [ ] App starts before tests
- [ ] Browser version pinned
- [ ] Fonts loaded before capture
- [ ] Animations disabled
- [ ] Time, random, locale frozen
- [ ] Auth state reused, never committed
- [ ] Volatile/sensitive regions masked
- [ ] Baselines reviewed before commit
- [ ] CI fails on new snapshots
