# Cluster A — ASCII Terminal Diagram

**🔴 DEFAULT TEMPLATE.** Use this when in doubt. Highest fidelity score (94-96% on first try). Cheapest to nail. ~45% of source corpus.

**Use case:** Pure system architecture / framework / diagram / pipeline / org chart.

**Look:** Two-tone monochrome, Unicode box-drawing, single monospace font, brutalist `man` page aesthetic.

> ⚠️ **Audit update (May 24, 2026):** Several Cluster A signatures were missing from the previous version. Now elevated to REQUIRED:
> - `◆` diamond separator in panel headers
> - `›` right-angle quote as canonical list bullet (NOT `→`)
> - "what runs here:" ritual line per panel
> - Inline `LEVEL N:` labels (NOT `[N]` bracketed numerals — that's Cluster C)
> - Bottom tagline is **LOWERCASE manifesto** (NOT ALL CAPS — that's Cluster C)

---

## Placeholders to fill

- `[LOWERCASE TITLE]` — e.g. "a typical agent stack"
- `[N]` — number of panels (recommend 3-5)
- For each panel: `[LABEL]` (e.g. "LEVEL 1", "LAYER 1"), `[SUBJECT]`, `[TAGLINE]`, `[FLOW]`, `[2 LINES PROSE]`, `[4 ITEMS]`
- `[BOTTOM TAGLINE]` — lowercase manifesto, ending in `.`
- `[HANDLE]` — e.g. `@yourhandle`
- `[USE_RIGHT_RAIL]` — optional: yes/no (adds `CONTROL STATION` sidebar)

## Prompt

```
A vertical Twitter/X infographic poster, portrait 2:3 aspect ratio.
Two-tone monochrome: warm near-black background #0E0E0E (pure #000 is also OK), bone off-white foreground #EAEAEA. Zero accent colors. No gradients, no shadows, no rounded corners.

Render the entire image in a single monospace font (Berkeley Mono / JetBrains Mono / IBM Plex Mono style), regular weight, fixed character grid. Lowercase body text, ALL CAPS section labels — but inline within panel borders.

Title at top:
  "[LOWERCASE TITLE]"
underlined by a single thin horizontal rule of dashes spanning the page width.

Below, [N] stacked rectangular panels drawn with thin Unicode box-drawing characters (┌ ─ ┐ │ └ ┘). Each panel has its label inset into the top border, with the canonical signature pattern:

┌─ LEVEL 1: [SUBJECT] ◆ [TAGLINE] ──────────────────┐

The ◆ DIAMOND SEPARATOR between subject and tagline is REQUIRED — it is THE Cluster A signature. Always include it.

DO NOT use `[1]` or `[2]` bracketed numerals — those are Cluster C convention. Cluster A uses inline `LEVEL 1:` / `LAYER 1:` / `STAGE 1:` labels in the top border.

Inside each panel:
  1. A small ASCII flow diagram with filled triangular arrowheads (X ──▶ Y style)
  2. A 2-line lowercase prose description
  3. The RITUAL line in lowercase: "what runs here:" (this exact phrase, always present)
  4. A 4-item example list, each prefixed with the `›` right-angle quote character — NOT `→` arrows, NOT `•` bullets. The `›` is the canonical Cluster A list bullet.

Example panel content:

┌─ LEVEL 1: main agent ◆ your prototype bench ──────┐
ASCII flow: you ──▶ hermes ──▶ output
prose: one agent on your laptop. talk to it directly.
       no orchestration. no docker. just one agent.
what runs here:
  › personal assistant · daily summaries
  › prototype workflows · skill seed
  › memory + soul.md · brand voice
  › cron-free · just-in-time runs

Between panels: a single │ followed by ▼ as flow connector (vertical pipe with downward triangle).

[OPTIONAL RIGHT-RAIL SIDEBAR — when topic is an org chart or "what lives where"]
A full-height right-side sidebar (~25% width) labeled "CONTROL STATION" or "LIVES HERE" at the top in ALL CAPS. Below: a vertical stack of ◆-prefixed mini-cards listing what each panel "knows" or "owns".

Bottom: a single LOWERCASE manifesto tagline centered:
  "[BOTTOM TAGLINE in lowercase manifesto style, ending with .]"
with "[HANDLE]" right-aligned below.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; ·) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, MIDDLE-DOT).
• Symbol characters (◆ › ▼ → ─ ┌ ┐ │ └ ┘) must render as the actual unicode glyph, NEVER as the spelled-out word (DIAMOND, QUOTE, TRIANGLE, ARROW, DASH, BOX-CHARACTERS). Cluster A relies heavily on these — the `◆` must be a literal diamond, not "DIAMOND".
• Avoid any duplicate or stuttered words.

The aesthetic is a `man` page rendered as wall art — engineer-poet zine, terminal-core, brutalist minimalism. No icons, no illustrations, no emoji, no colors other than off-white on near-black.
```

## Cluster A signature checklist (audit-derived, REQUIRED)

✅ `◆` diamond separator in every panel header
✅ `›` right-angle quote as list bullet (NOT `→`, NOT `•`)
✅ "what runs here:" ritual line in every panel
✅ Inline `LEVEL N:` / `LAYER N:` labels (NOT `[N]` brackets)
✅ Lowercase body throughout
✅ LOWERCASE manifesto tagline at bottom (NOT ALL CAPS)
✅ `│ ▼` flow connector between stacked panels
✅ Single monospace font throughout
✅ Zero accent colors

🟡 Optional: right-rail sidebar (`CONTROL STATION` / `LIVES HERE`) for org-chart variants

## Production score

Cluster A consistently hits **94-99% on-brand on first generation** when the prompt includes:
- the `◆` diamond separator inside panel headers (the canonical signature)
- the `›` right-angle quote bullets
- the "what runs here:" ritual line at the bottom of each panel
- inline LEVEL/LAYER labels on panel borders

Without these motifs, the model drifts toward generic monospace zine layouts.

## Reference images

The Cluster A pattern was reverse-engineered from a corpus of public posts by [@shannholmberg](https://x.com/shannholmberg) on X. See his profile for the canonical examples — the "4 levels of Hermes setup", the "Hermes Agent control room", and the "org chart for my Hermes Agent company" posts are the three top performers in the cluster.
