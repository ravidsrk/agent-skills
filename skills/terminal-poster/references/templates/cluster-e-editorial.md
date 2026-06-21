# Cluster E — Editorial Brand Book

**Use case:** Brand identity reveal, design system showcase, voice doc, "the brand book". RARE — only ~4% of source corpus uses this format.

> ⚠️ **Audit update (May 24, 2026):** The previous version described a SINGLE cream page. **That was wrong.** The actual format is a **dark canvas with multiple cream brand-book pages floating on it** as a multi-page spread. The single-page description was the master page only — the composition is a multi-thumbnail layout.

**Look:** Dark composite canvas `#0D0D0D` with cream/white brand-book pages thumbnail-tiled across it. A 3×3 grid of small portrait page thumbnails on the left/middle + one enlarged master page on the right. Banded orange→peach aura gradient behind the hero headline. Editorial serif typography.

---

## Placeholders to fill

- `[BRAND NAME]` — what you're branding
- `[N THUMBNAILS]` — recommend 6-9 (a 3×3 grid)
- For each thumbnail page: `[NUMBER / SECTION NAME]`, `[CONTENT]`
- `[ENLARGED MASTER PAGE]` — the hero headline + tagline + 1 visual element
- `[HERO HEADLINE]` — e.g. "BookMarkable" in Instrument Serif
- `[HERO TAGLINE]` — short editorial sub-line in italic
- `[BOTTOM HANDLE]` — small caps Inter

## Prompt

```
A vertical Twitter/X infographic poster, portrait 2:3 aspect ratio. High-end editorial brand-book aesthetic, multi-page spread composition.

CANVAS: dark #0D0D0D backdrop — this is the FRAME, not the page color. The dark canvas allows multiple cream brand-book pages to float on it as a composite layout. Subtle warm orange→peach gradient leaking from the top-right corner of the canvas (banded / stacked-light-leak look, NOT a smooth radial — think 1970s film grain meets Risograph).

LAYOUT — a multi-page brand-book spread:
  LEFT 2/3 of canvas: a 3×3 grid of portrait page thumbnails. Each thumbnail is a small cream-paged brand-book page (cream/white #FFFFFF background, dark charcoal #0D0D0D text). Tiny scale — readable as "this is a brand book page" but content is suggestive, not legible at full detail.
  RIGHT 1/3 of canvas: one ENLARGED master page at readable scale, also cream/white. This is the hero card.

Each thumbnail page (3×3 grid, label them sequentially):
  Thumbnail content rotates through brand-book section types:
    "01 / BRAND IDEA" — the elevator pitch in 1-2 serif paragraphs
    "02 / PALETTE" — 4-6 color swatches with hex codes (use Cluster E palette below)
    "03 / TYPOGRAPHY" — font specimens (display, body, mono)
    "04 / SHADER + UI" — visual primitives, button styles, card patterns
    "05 / VOICE" — 3-5 tone bullets
    "06 / IMAGE MODEL PROMPT" — the reproducible prompt for generating brand imagery
    "07 / LOGOMARK" — logo variations
    "08 / ICONOGRAPHY" — small bookmark/ribbon icon set
    "09 / SHIPPING" — example final assets

Each thumbnail label uses Inter caps letter-spaced, with `01 /` numerical prefix in small caps.

ENLARGED MASTER PAGE (right 1/3):
  - Brand name "[BRAND NAME]" set XL in **Instrument Serif** display (elegant serif with high contrast strokes)
  - Below in italic Inter or italic Instrument Serif: "[HERO TAGLINE]"
  - The banded orange→peach aura gradient sits BEHIND this headline — like stacked horizontal light-leaks, not a smooth radial. Think Risograph print layers.
  - Below the headline: one visual element — could be a small bookmark icon, a wordmark, or a peach swatch.

Fonts (this is editorial — different from other clusters):
  - Display: Instrument Serif
  - Body: Inter (clean modern sans-serif)
  - Numbers/labels: Inter caps, letter-spaced

Editorial palette (Cluster E specific):
  - Pitch Black #0D0D0D (canvas)
  - Cream #FFFFFF (page bg)
  - Bookmark Red #FC4A2B (primary accent — NOT Hermes orange)
  - Save Orange #F7A488 (peach — for the aura gradient)
  - Confirm Green #1E8E3E (active state)
  - Ash Gray #8E8E8E (secondary text)

Bottom of canvas (below the spread): a thin horizontal divider line, then a single italic Instrument Serif tagline centered — SENTENCE CASE not all caps:
  "[BOTTOM TAGLINE in sentence case italic]"
with "[BOTTOM HANDLE]" right-aligned in small caps Inter below.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; — /) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, EM-DASH, SLASH). The `/` in section labels like "01 / BRAND IDEA" must render as a literal slash character.
• Symbol characters used in editorial layouts must render as glyphs, not letters.
• Avoid any duplicate or stuttered words.

Aesthetic: a magazine-quality brand identity spread for a high-end editorial publication shot on velvet — page thumbnails arranged like a museum vitrine. Warm, contemplative, serious. Zero terminal/cyberpunk elements. The dark canvas is the showcase wall; the cream pages are the artifacts. Subtle paper-grain texture acceptable on pages, not on canvas.
```

---

## When to choose this

- Topic IS brand identity / voice / design system
- Audience is designers, brand strategists, creative directors
- The poster itself is a brand artifact, not a feature explainer

🟡 **Use sparingly.** Only ~4% of source corpus uses this format. Most posters should NOT use Cluster E.

## Signature motif checklist

- ✅ Dark canvas (NOT cream — canvas is `#0D0D0D`, pages are cream)
- ✅ 3×3 page thumbnail grid + 1 enlarged master page
- ✅ Banded orange→peach aura gradient behind hero (stacked light-leak, not smooth radial)
- ✅ Instrument Serif display + Inter body
- ✅ `01 / SECTION` numbered page labels
- ✅ Small bookmark/ribbon icons on palette pages
- ✅ Sentence-case editorial tagline (NOT ALL CAPS — this is the one cluster that breaks the case rule)
- ✅ Bookmark red `#FC4A2B` as primary accent (NOT Hermes orange `#F26B1F`)
