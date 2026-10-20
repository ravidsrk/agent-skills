// e2e/finish/finish-fixture.ts — installed by the finish-line skill. Do not weaken.
//
// Every Finish Line spec imports { test, expect } from './finish-fixture' instead of '@playwright/test'.
// A test fails automatically on:
//   - any console.error or uncaught page error
//   - any HTTP response >= 400, or failed request, that the test didn't declare with allowHttpError()
// Helpers:
//   snap(step)          full-page screenshot → .finish/evidence/<ITEM-ID>/<project>-<test>-<nn>-<step>.png
//   a11y()              axe scan of the current page; fails on serious/critical WCAG 2.1 A/AA violations
//   allowHttpError({ status, url })   declare an error response a criterion expects (e.g. 409 on duplicate signup)
// The item ID comes from the spec file name: e2e/finish/J-001.spec.ts → J-001.
import { test as base, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import fs from 'node:fs';
import path from 'node:path';

type HttpAllow = { status?: number; url?: RegExp };
type FinishState = { httpAllow: HttpAllow[]; problems: string[] };

export type FinishFixtures = {
  itemId: string;
  finishState: FinishState;
  snap: (step: string) => Promise<string>;
  a11y: () => Promise<void>;
  allowHttpError: (rule: HttpAllow) => void;
};

const EVIDENCE_ROOT = process.env.FINISH_EVIDENCE_DIR ?? path.resolve(process.cwd(), '.finish', 'evidence');
const slug = (s: string, max = 40) =>
  s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, max) || 'step';

const allowed = (rules: HttpAllow[], status: number, url: string) =>
  rules.some((r) => (r.status === undefined || r.status === status) && (r.url === undefined || r.url.test(url)));

export const test = base.extend<FinishFixtures>({
  itemId: async ({}, use, testInfo) => {
    await use(path.basename(testInfo.file).split('.')[0]);
  },

  finishState: async ({}, use) => {
    await use({ httpAllow: [], problems: [] });
  },

  page: async ({ page, finishState }, use) => {
    const s = finishState;
    page.on('console', (msg) => {
      if (msg.type() !== 'error') return;
      // Failed resource loads are reported (and allow-listed) by the response/requestfailed handlers below.
      if (msg.text().startsWith('Failed to load resource')) return;
      s.problems.push(`console.error: ${msg.text()}`);
    });
    page.on('pageerror', (err) => s.problems.push(`pageerror: ${err.message}`));
    page.on('response', (res) => {
      const status = res.status();
      if (status >= 400 && !allowed(s.httpAllow, status, res.url())) {
        s.problems.push(`HTTP ${status}: ${res.request().method()} ${res.url()}`);
      }
    });
    page.on('requestfailed', (req) => {
      const reason = req.failure()?.errorText ?? 'failed';
      if (reason.includes('ERR_ABORTED')) return; // navigation cancelled an in-flight request
      if (!allowed(s.httpAllow, 0, req.url())) s.problems.push(`request failed (${reason}): ${req.method()} ${req.url()}`);
    });

    await use(page);

    expect(s.problems, 'Unexpected console errors, page errors or HTTP failures').toEqual([]);
  },

  allowHttpError: async ({ finishState }, use) => {
    await use((rule) => {
      finishState.httpAllow.push(rule);
    });
  },

  snap: async ({ page, itemId }, use, testInfo) => {
    let n = 0;
    await use(async (step) => {
      n += 1;
      const dir = path.join(EVIDENCE_ROOT, itemId);
      fs.mkdirSync(dir, { recursive: true });
      const name = `${testInfo.project.name}-${slug(testInfo.title)}-${String(n).padStart(2, '0')}-${slug(step)}.png`;
      const file = path.join(dir, name);
      await page.screenshot({ path: file, fullPage: true });
      await testInfo.attach(step, { path: file, contentType: 'image/png' });
      return file;
    });
  },

  a11y: async ({ page }, use) => {
    await use(async () => {
      const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
      const bad = results.violations
        .filter((v) => v.impact === 'serious' || v.impact === 'critical')
        .map((v) => `${v.impact}: ${v.id} — ${v.help} (${v.nodes.length} nodes: ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(' | ')})`);
      expect(bad, `Serious/critical accessibility violations on ${page.url()}`).toEqual([]);
    });
  },
});

export { expect };
