#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scaffold.sh [options]

Create a minimal Playwright visual-regression setup.

Options:
  --dir DIR      Target directory (default: .)
  --url URL      App URL used as Playwright baseURL (default: http://localhost:3000)
  --force        Overwrite existing files
  -h, --help     Show this help

Writes:
  playwright.config.ts
  tests/visual/home.spec.ts

Never runs the tests and never installs packages.
EOF
}

dir="."
url="http://localhost:3000"
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] || { echo "missing value for --dir" >&2; exit 2; }; dir="$2"; shift 2 ;;
    --url) [ $# -ge 2 ] || { echo "missing value for --url" >&2; exit 2; }; url="$2"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$dir/tests/visual"

write_file() {
  local path="$1"
  if [ -e "$path" ] && [ "$force" -ne 1 ]; then
    echo "skip (exists): $path"
    return 0
  fi
  cat > "$path"
  echo "wrote: $path"
}

write_file "$dir/playwright.config.ts" <<EOF
import { defineConfig, devices } from "@playwright/test";

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
    baseURL: process.env.APP_URL ?? "${url}",
    colorScheme: "light",
    deviceScaleFactor: 1,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "mobile", use: { ...devices["Desktop Chrome"], viewport: { width: 375, height: 812 } } },
  ],
});
EOF

write_file "$dir/tests/visual/home.spec.ts" <<'EOF'
import { test, expect } from "@playwright/test";

test("home renders", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => document.fonts.ready);
  await expect(page).toHaveScreenshot("home.png", {
    fullPage: true,
    mask: [page.locator("[data-private]")],
  });
});
EOF

cat <<EOF

Next steps:
  npm i -D @playwright/test
  npx playwright install --with-deps chromium
  APP_URL=${url} npx playwright test tests/visual --update-snapshots
  # review every generated image, then commit it
  APP_URL=${url} npx playwright test tests/visual
EOF
