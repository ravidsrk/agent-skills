// Example only — the shape of a Finish Line spec. Real specs live at e2e/finish/<ID>.spec.ts.
// Rules: one test per acceptance criterion, titled with the criterion text verbatim;
// real backend and database; unique data per run; snap() at each key step; a11y() on each P0 screen;
// allowHttpError() only for an error response the criterion itself expects.
import { execSync } from 'node:child_process';
import { test, expect } from './finish-fixture';

const email = () => `finish+${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.test`;
const PASSWORD = 'Correct-Horse-Battery-9';

async function signUp(page: import('@playwright/test').Page, address: string) {
  await page.goto('/signup');
  await page.getByLabel(/email/i).fill(address);
  await page.getByLabel(/password/i).fill(PASSWORD);
  await page.getByRole('button', { name: /sign up|create account/i }).click();
}

test('Given a new email, when the user completes signup, then they land on /dashboard', async ({ page, snap, a11y }) => {
  await page.goto('/signup');
  await snap('signup form');
  await a11y();

  await signUp(page, email());

  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible();
  await snap('empty dashboard');
  await a11y();
});

test('Given an already-registered email, when the user signs up, then an inline error is shown and no account is created', async ({ page, snap, allowHttpError }) => {
  const address = email();
  await signUp(page, address);
  await expect(page).toHaveURL(/\/dashboard$/);
  await page.context().clearCookies();

  allowHttpError({ status: 409, url: /\/api\/.*sign-?up/ }); // the duplicate attempt is expected to be rejected
  await signUp(page, address);

  await expect(page.getByRole('alert')).toContainText(/already/i);
  await expect(page).toHaveURL(/\/signup/);
  await snap('duplicate email error');

  // "no account is created": still exactly one row in the real database (adapt table/column to the app)
  const rows = execSync(`psql "$DATABASE_URL" -tAc "select count(*) from users where email = '${address}'"`).toString().trim();
  expect(Number(rows)).toBe(1);
});

test('Given a signed-up user, when they reload /dashboard, then they are still signed in', async ({ page, snap }) => {
  await signUp(page, email());
  await expect(page).toHaveURL(/\/dashboard$/);

  await page.reload();

  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole('heading', { name: /dashboard/i })).toBeVisible();
  await snap('dashboard after reload');
});
