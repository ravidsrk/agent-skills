# Fix playbook

Fix in impact-per-minute order. One change at a time; re-scan after each batch.

# 1. Rewrite the H1

Formula: `[concrete category] for [specific audience]`.

| Weak | Strong |
|---|---|
| "Reimagine your workflow" | "Issue tracking for product teams" |
| "The future of email" | "Email API for developers" |
| "AI-powered growth platform" | "Meeting notes that write themselves" |
| "Build faster" | "Ship a landing page in an afternoon" |

Test: replace the product name with "X". Does the H1 still say what X does and who it is for? If not, rewrite.

# 2. Remove the fake-news eyebrow

Keep an eyebrow only if it carries verifiable news:

- "v2.3 shipped today"
- "Used by 800 teams"
- "Backed by YC W26"

Remove sparkles, "AI-powered", "Now in beta", and pulsing dots. If you do not have real news, omit the eyebrow entirely.

# 3. Replace the generic CTA

| Weak | Strong |
|---|---|
| "Sign up" | "Start my free trial" |
| "Get started" | "See the live demo" |
| "Learn more" | "Read the 3-minute setup" |
| "Contact us" | "Book a 15-minute call" |

The CTA should name the user's outcome, not the generic action.

# 4. Pick one accent on a flat surface

- One accent color, used for the primary action and one highlight.
- Flat background: dark `#0e0e0f`, warm off-white, or editorial black.
- Remove blue→purple gradients, aurora blobs, glass panels, and colored glows.
- If you keep a gradient, it must be a product visual, not the page background.

# 5. Replace the three-icon card trio

The "Lightning fast / Beautiful design / Easy to use" grid is the strongest template tell. Replace it with one product-narrative section:

- a code switcher for developer tools
- an animated terminal or transcript for agents/voice
- a workflow loop for orchestration
- a real screenshot for visual products
- a customer story with a named, attributable person

At least one section before the feature list must show the moment of magic.

# 6. Reduce motion

- One purposeful animation per page, maximum.
- No fade-up on every section.
- No `scale(1.05)` on every card.
- Respect `prefers-reduced-motion`.
- Static typography with good hierarchy reads as more crafted than motion everywhere.

# 7. Typography

Use three roles:

- display: distinctive, 1–2 weights
- body: readable, 1–2 weights
- mono: code, numbers, labels only

Tune tracking per size:

- H1: -0.03 to -0.04em
- H2: -0.02em
- H3: -0.01em
- body: 0

Do not blanket `tracking-tight`; do not use Inter/Geist as the only face.

# 8. Custom OG image

Every page needs a 1200×630 social card with the project name, value prop, and a signature visual.

```html
<meta property="og:image" content="https://example.com/og.png" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:alt" content="Product name — value proposition" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:image" content="https://example.com/og.png" />
```

Verify the rendered card at a social preview debugger. A framework-default `/og.png` or no image at all is a failure.

# 9. Fix AEO blockers

1. Serve real HTML (not a client-only shell).
2. Allow search indexing on public pages.
3. Remove accidental bot/CDN blocks.
4. Fix JSON-LD types and URLs.
5. Add a Markdown twin and `rel=alternate` if the content benefits.
6. Add `llms.txt` and visible dates.

See `aeo.md` for the 16 checks.

# 10. Design-system drift

If a `DESIGN.md` exists, fix the token or the component. Do not edit the spec to match a one-off page. If the campaign intentionally breaks the system, record the exception and its scope.

# Lateral moves to avoid

These replace one slop pattern with another:

- Inter → Geist or Plus Jakarta Sans
- Indigo-600 → Violet-600
- Linear gradient text → radial gradient text
- Three-icon trio → three numbered steps with icons
- Sparkle eyebrow → "New" pill with a pulsing dot
- Fade-up on every section → fade-in on every section
- Fake terminal → fake browser window

# Re-scan

After each batch:

```bash
bash scripts/scan.sh "$URL" --design --aeo
```

Success means the same pattern no longer triggers, not that the score moved by one point. Keep the before/after report with the PR.
