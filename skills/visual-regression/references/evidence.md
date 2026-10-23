# Evidence artifacts

Screenshots prove a state. Videos prove an interaction. Both are evidence for a reviewer who was not watching the run.

# Choose the mode

| Need | Mode |
|---|---|
| Above-the-fold layout, one state | Viewport screenshot |
| Whole document, vertical content matters | Full-page screenshot |
| Open menu, drag, type, navigate, animation, multi-step flow | Video |
| Before/after comparison | Two screenshots at the same viewport |
| Component-level check | Element screenshot |

State the mode explicitly. "I took a screenshot" is not enough; say whether it was viewport, full-page, element, or video, and at what size.

# Playwright screenshots

```ts
import { test, expect } from "@playwright/test";

test("settings header", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/settings");
  await page.evaluate(() => document.fonts.ready);
  await expect(page).toHaveScreenshot("settings-header.png", { fullPage: false });
});
```

For an evidence file outside the assertion flow:

```ts
await page.screenshot({ path: "artifacts/settings.png", fullPage: false });
await page.locator("[data-testid=invoice-card]").screenshot({ path: "artifacts/invoice.png" });
```

# Playwright video

```ts
// playwright.config.ts
use: {
  video: "retain-on-failure",
  viewport: { width: 1440, height: 900 },
}
```

Or record a specific interaction:

```ts
const context = await browser.newContext({
  recordVideo: { dir: "artifacts/", size: { width: 1440, height: 900 } },
});
const page = await context.newPage();
await page.goto("/settings");
await page.getByTestId("open-menu").click();
await page.getByRole("menu").waitFor();
await context.close(); // flushes the video
```

Video dimensions are the encoded dimensions, not necessarily the requested viewport. Probe the file before reporting:

```bash
ffprobe -v error -show_entries stream=width,height,duration -of json artifacts/video.webm
```

# Metadata contract

Every artifact should carry:

| Field | Example | Required |
|---|---|---|
| path or artifact ID | `artifacts/settings.png` | yes |
| caption | "Settings header after the spacing fix" | yes |
| source URL | `http://localhost:3000/settings` | yes |
| mode | viewport / full-page / element / video | yes |
| viewport | `1440x900` | yes |
| captured at | ISO timestamp | recommended |
| duration | video only, from `ffprobe` | video |
| dimensions | video only, from `ffprobe` | video |
| commit or run ID | `abc1234` | recommended |

Do not claim an artifact was attached unless the upload command or platform returned an ID/path.

# Attaching to a review

Use the host the team already uses:

- PR comment with the artifact link and the caption
- issue attachment
- CI artifact upload (retained for 7 days)
- MCP/session upload tool when one is available

Example comment:

```text
Verified the settings header spacing fix.
Mode: viewport
Viewport: 1440x900
Source: http://localhost:3000/settings
Artifact: artifacts/settings-1440.png
```

# Redaction

Before capture:

- mask emails, names, avatars, tokens, addresses, and billing amounts
- use fictional fixtures, not production data
- hide browser chrome and OS notifications
- avoid recording a screen that shows another app or a terminal with secrets

```ts
await expect(page).toHaveScreenshot("account.png", {
  mask: [page.locator("[data-private]"), page.getByTestId("email")],
});
```

# Retention

- CI artifacts: 7–14 days.
- PR evidence: keep the link for the life of the PR.
- Baselines: keep until the surface is removed.
- Raw videos: delete after review unless they document a shipped decision.

# Guardrails

- Do not leave an active recording running. Stop it in a `finally` block or after `context.close()`.
- Do not reuse a requested viewport as the video dimensions. Read the encoded file.
- Do not upload to a public store from a private repo without checking the sensitivity of the pixels.
- Do not report a screenshot as proof of an interaction; use a video when time matters.
- If the capture fails, report the failure. Do not silently fall back to an older artifact.
