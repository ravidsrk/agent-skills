// e2e/finish/playwright.config.ts — Finish Line E2E config (installed by the finish-line skill).
// Runs every spec at phone and desktop size against the real local stack started by .finish/init.sh.
// Point at a deployed preview with BASE_URL=https://…, or at a fresh clone's app with PORT=3100.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: /.*\.spec\.ts$/,
  forbidOnly: true,
  retries: 0,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  outputDir: '../../.finish/evidence/_playwright',
  use: {
    baseURL: process.env.BASE_URL ?? `http://localhost:${process.env.PORT ?? 3000}`,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'phone',
      use: { ...devices['Desktop Chrome'], viewport: { width: 375, height: 812 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 },
    },
    {
      name: 'desktop',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } },
    },
  ],
});
