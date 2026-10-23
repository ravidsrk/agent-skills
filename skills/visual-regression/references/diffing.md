# Diffing

# Pixel diff vs perceptual diff

A raw pixel diff counts changed pixels. It is fast and explainable, but it treats anti-aliasing, font hinting, and one-pixel shifts as failures.

A perceptual diff compares how the image looks to a human: luminance (YIQ), local structure (SSIM variants), and color. It is better at ignoring rendering noise while still catching real layout, spacing, and color changes.

Use pixel diff for small, stable component screenshots. Use a perceptual threshold for full pages and cross-machine CI.

# Recommended thresholds

| Surface | Metric | Start |
|---|---|---|
| Component / small element | `maxDiffPixelRatio` | 0.001–0.002 |
| Full page, same machine | `maxDiffPixelRatio` | 0.002–0.005 |
| Full page, cross-machine | perceptual (Chroma-SSIM / CW-SSIM) | 0.01–0.02 |
| Text-heavy page | perceptual + font pinning | 0.005–0.01 |

Tune from real runs. A threshold that hides a 4px spacing shift is too loose. A threshold that fails on anti-aliasing is too tight.

# Playwright snapshot options

```ts
await expect(page).toHaveScreenshot("home.png", {
  maxDiffPixels: 40,
  maxDiffPixelRatio: 0.002,
  threshold: 0.2,          // per-pixel color tolerance (0–1)
  animations: "disabled",
  caret: "hide",
  mask: [page.getByTestId("avatar"), page.getByTestId("timestamp")],
  maskColor: "#ff00ff",
  fullPage: false,
  scale: "css",
});
```

- `threshold` controls per-pixel color distance; `maxDiffPixels`/`maxDiffPixelRatio` control how many pixels may differ.
- `mask` paints a solid rectangle over volatile content before capture. Prefer masks over deleting content from the DOM.
- `animations: "disabled"` fast-forwards CSS animations and transitions to their end state.

# Perceptual metrics

If you use Frontguard or build your own comparator:

- **YIQ** — separates luminance from chrominance. Good for detecting brightness and contrast shifts.
- **Chroma-SSIM** — structural similarity on chroma channels. Good for color and gradient changes.
- **CW-SSIM** — complex-wavelet SSIM. More tolerant of small translations and font rendering differences.

Cluster diffs by nearby bounding boxes and shared selectors. One root cause often produces a dozen screenshots; fixing it once is cheaper than reviewing twelve images.

# Stabilization

The most common cause of false diffs is an unstable render, not a regression.

- Wait for `document.fonts.ready`.
- Wait for network idle and known API responses.
- Disable CSS animations, transitions, video, carousels, and marquees.
- Freeze clocks and relative dates.
- Replace random values with a seeded value.
- Mock ads, maps, chat widgets, and live feeds.
- Wait for images to decode (`img.decode()`).
- Scroll the page to trigger lazy content, then return to the top.
- Give the layout one animation frame to settle before capture.

# Redaction

Mask before capture, not after:

```ts
const sensitive = [
  page.getByTestId("user-email"),
  page.getByTestId("api-key"),
  page.getByTestId("billing-amount"),
  page.locator("[data-private]"),
];
await expect(page).toHaveScreenshot("settings.png", { mask: sensitive });
```

Also consider:

- hiding avatars and names in screenshots intended for a public PR
- blurring addresses, phone numbers, tokens, and order IDs
- using fixtures with fictional data, not production copies
- never uploading screenshots that contain secrets to a public artifact store

# Dark mode

Set the color scheme explicitly per project:

```ts
use: { colorScheme: "dark" }
```

Do not rely on the host OS. A machine-level dark-mode change should not rewrite every baseline.

# Flaky screenshots

A screenshot that passes only sometimes is worse than no screenshot: it trains the team to re-run CI.

1. Run the same test ten times (`--repeat-each=10`).
2. Diff the actual images against each other.
3. If the images differ, fix the render; do not raise the threshold.
4. If the images are identical but the comparison flakes, pin the browser and OS.

# Interpreting a failure

| Pattern | Likely cause |
|---|---|
| Whole page shifted a few pixels | Scrollbar, viewport, or font metrics changed |
| One component changed | Real CSS/component change |
| Text only | Font loading, fallback font, or anti-aliasing |
| Color-only change | Theme token, opacity, or color profile |
| Random regions | Volatile data not masked |
| Everything changed after a browser bump | Rendering engine change; re-baseline and review |

# Never do this

- `--update-snapshots` in CI.
- Promoting a baseline without viewing the diff.
- Raising the threshold until the test passes.
- Masking a region because it is inconvenient rather than volatile.
- Comparing screenshots from different browser versions, OSes, or device scale factors.
