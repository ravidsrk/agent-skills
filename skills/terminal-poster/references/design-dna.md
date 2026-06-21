# Terminal-Poster Design DNA

The common pattern across all 5 clusters. If you can only remember 10 things, remember these.

> ⚠️ **Read this carefully:** many rules are **cluster-specific**, not universal. The previous version of this doc over-generalized from a single Cluster C reference. This version is audited against 12 real images.

# Color rules

## Background — depends on cluster
| Cluster | Background | Notes |
|---|---|---|
| A (ASCII Terminal) | `#0E0E0E` warm charcoal | Sometimes drifts to pure `#000` — both valid |
| B (Color-Coded) | `#0A0A0A` or `#000` | High-contrast for neon accents |
| C (Cyborg Hero) | `#0E0E0E` warm charcoal | With subtle ambient orange glow |
| D1 (Step Pipeline) | `#0D0D0D` near-black | Often with dotted blueprint grid overlay |
| D2 (Terminal Window) | Painterly mossy canvas OUTSIDE the fake window | Window inside is `#0E0E0E` |
| E (Editorial) | `#0D0D0D` DARK canvas + cream/white pages floating on it | NOT a single cream page |

🟡 **The "NEVER pure black `#000`" rule was wrong.** Use `#0E0E0E` warm charcoal as the *default* (for Cluster A and C), but pure `#000` is fine and common for high-neon Cluster B and dark composite canvases (Cluster E).

## Foreground
| Token | Hex | Used for |
|---|---|---|
| Primary fg | `#EAEAEA` | Bone off-white — body text on dark bg |
| Cream body | `#F0E6D2` | Cluster C card body (warmer) |
| Muted tan | `#A89680` | Secondary body, captions, version stamps |

## Orange — Shann uses a RANGE, not one hex
| Hex | Name | When |
|---|---|---|
| `#F26B1F` | **Hermes orange** | 🔴 Cluster C primary — numbered badges, hero accents, gBrain reference |
| `#FF8C2E` | Warm signature orange | Control Room, mixed-neon badges |
| `#B8541F` | **Muted rust** | 🟡 Cluster B specialist accent (less saturated, "corporate") |
| `#FF9500` | Amber orange | Sales / L4 columns in color-coded posters |
| `#FF6A1A` | Vivid red-orange | "Ultimate Hermes Army" style headlines |
| `#FC4A2B` | Red-orange | Cluster E (BookMarkable family) |

🔴 **Use `#F26B1F` only when generating Cluster C in the gBrain/Hermes lineage.** For Cluster B, prefer muted rust `#B8541F`. For Cluster E, use red-orange `#FC4A2B`. The "vivid Hermes orange" assumption breaks Cluster B/E if applied uniformly.

## Secondary accents
| Token | Hex | Cluster |
|---|---|---|
| Phosphor green | `#A8E060` | Terminal text, **primary accent for Cluster D1** (NOT orange) |
| Cyan | `#00D9D9` | Cluster B/C tertiary, system labels |
| Magenta | `#B57FFF` | Cluster B/C tertiary, "the stack" callouts |
| Gold | `#E8C547` | Cluster B/C tertiary, premium feature |
| Bookmark red | `#FC4A2B` | Cluster E primary |
| Save peach | `#F7A488` | Cluster E secondary |
| Confirm green | `#1E8E3E` | Cluster E "active" state |

# Typography rules

| Cluster | Display | Body |
|---|---|---|
| A | single monospace (Berkeley Mono, JetBrains Mono, IBM Plex Mono) | same monospace |
| B | Inter / Geist | Inter / Geist |
| C | Press Start 2P / VT323 (pixel-bitmap) | monospace |
| D1 | Press Start 2P (headline only) | monospace |
| D2 | Single monospace throughout (matches A) | same monospace |
| E | Instrument Serif | Inter |

## Case rules — cluster-specific
| Cluster | Body | Section labels | Tagline |
|---|---|---|---|
| A | lowercase | ALL CAPS / `LEVEL N:` inline | **lowercase manifesto** (NOT all caps) |
| B | lowercase | ALL CAPS letter-spaced | **lowercase, middle-dot separated** |
| C | mixed | ALL CAPS | **ALL CAPS, period/pipe/star separated** |
| D1 | lowercase | ALL CAPS | short ALL CAPS punchline |
| D2 | lowercase | inline section labels | terminal `zsh$` prompt at bottom |
| E | sentence case | Inter small caps | editorial italic Instrument Serif |

🔴 **The "universal ALL CAPS period-separated tagline" rule was wrong.** Only Cluster C uses it. Cluster A/B taglines are lowercase. Cluster E is editorial italic.

# Layout rules

- Vertical 2:3 aspect ratio for X posts (portrait orientation) — Cluster A, B, C, E
- Cluster D uses 3:4 for landscape-feeling pipelines
- Cluster E uses 2:3 but with a 3×3 grid of thumbnail "pages" + 1 master page enlarged
- Grid system: 12-column dark grid, content snapped to it
- Generous padding inside panels; tight gutters between panels

# Decorative elements (required when applicable)

## Universal (all clusters when applicable)
- 🔴 **Bottom tagline** — always present, format varies by cluster (see Case rules table)
- 🔴 **Handle bottom-right** — `@handle` in muted tan
- 🟡 **`→` arrows** for explicit data flow (NOT for Cluster A list bullets — those use `›`)

## Cluster A signatures (REQUIRED for Cluster A — these are what make it "feel right")
- 🔴 **`◆` diamond separator** in panel headers: `┌─ LEVEL 1: main agent ◆ your prototype bench ─┐`
- 🔴 **`›` right-angle quote bullet** — the canonical Cluster A list bullet (`› item 1 · item 2`)
- 🔴 **"what runs here:" ritual line** in each panel, followed by 4-item example list
- 🔴 **Inline `LEVEL N:` / `LAYER N:` labels** in panel top borders (NOT `[N]` bracketed numerals — that's Cluster C)
- 🟡 **Optional right-rail sidebar** (`CONTROL STATION` / `LIVES HERE` / `WHAT IT KNOWS`) for org-chart-style images
- 🟡 **`│ ▼` flow connectors** between stacked panels

## Cluster C signatures
- 🔴 **Terminal prompts in BOTH corners** — top-left `> [topic]$ [status]` in green mono, top-right `> sys$ [status_2]  @[handle]` in muted tan (SECOND prompt, NOT a `v1.0.0` version stamp)
- 🔴 **`[1] [2] [3]` numbered badges** in square brackets OR filled colored squares (Cluster C convention, NOT Cluster A)
- 🔴 **ALL CAPS tagline bar at bottom** — separators: `.`, `|`, or `★`
- 🟡 **Mode C1 painterly hero** with 5 composition rules: tight chest-up shot, left-third rule-of-thirds, NO halo, three-quarter rear view, lived-in grit
- 🟡 **Mode C2 flat pixel hero** as alternative for whimsical topics
- 🟡 **Pixel-art robot mascot** in tagline bar — clean+bold+iconic, ~14% of bar height
- 🟡 **Stack-equation centerpiece** on a fake monitor: `X = THE BRAIN / Y = THE BODY`
- 🟡 **Plus-chain equation footer**: `A + B + C + D = outcome`

## Cluster D signatures
- 🔴 **macOS traffic-light dots** (red/yellow/green circles) top-left when content is framed as a terminal/editor window — required for D2, common in D1
- 🔴 **Phosphor green `#A8E060` is primary accent for D1** (NOT orange)
- 🟡 **Dashed-border step cards** for D1
- 🟡 **`zsh$` prompt line** at very bottom of D2 for terminal realism
- 🟡 **`✦` star-callout** for D1 bottom manifesto

## Cluster E signatures
- 🔴 **Dark canvas `#0D0D0D` with cream pages floating on it** — NOT a single cream page
- 🔴 **3×3 thumbnail grid + 1 enlarged master page** composition
- 🔴 **Banded orange→peach aura gradient** behind hero headline (stacked light-leak look, NOT smooth radial)
- 🟡 **Small bookmark/ribbon iconography** on palette pages

# What's forbidden (audited — these still hold)

- ❌ Drop shadows (except as part of hero illustration in Cluster C Mode C1)
- ❌ Rounded corners outside Cluster B cards (max 8px) and Cluster D step cards
- ❌ Pure `#FFF` foreground (use `#EAEAEA` or `#F0E6D2`)
- ❌ Sentence-case body text in A/B/C/D
- ❌ Emoji 🚀 — source corpus uses zero standard emoji
- ❌ Stock photos
- ❌ Decorative flourishes that don't earn their pixel
- ❌ **`[N]` bracketed numerals in Cluster A** (use inline `LEVEL N:` instead — `[N]` is Cluster C convention)
- ❌ **`•` bullet at the START of list items.** `·` middle-dot is OK as INLINE separator between phrases.

# What's mandatory (audited — these still hold)

- ✅ Dark background (warm `#0E0E0E` default; pure `#000` OK for B/E composite canvas)
- ✅ Bone `#EAEAEA` foreground (or `#F0E6D2` cream for Cluster C card bodies)
- ✅ At least one orange element — but pick the right hex for the cluster (see Orange table above)
- ✅ Bottom tagline + handle right-aligned
- ✅ Either ASCII box-drawing OR pixel-bitmap headline OR painterly hero (depends on cluster)
- ✅ Sharp 1-2px strokes throughout body content
- ✅ Engineered, not painted — **except hero zones in Cluster C Mode C1 and the canvas in Cluster D2**

# Updated: what about gradients?

🔴 **Earlier "zero gradients" rule was wrong.** Audited reality:

- ✅ **Allowed:** Radial ambient orange glow behind Cluster C hero (Mode C1)
- ✅ **Allowed:** Banded orange→peach aura gradient behind Cluster E hero headline
- ✅ **Allowed:** Painterly textured canvas for Cluster D2 OUTSIDE the fake terminal window
- ❌ **Forbidden:** Gradients inside body cards or grid sections (still flat there)
- ❌ **Forbidden:** Smooth color gradients anywhere in Cluster A

# 🔴 The shared text-rules block (paste into ANY prompt with a tagline or symbol-separated text)

Models trained on common text patterns will sometimes spell out the word "PERIOD" instead of rendering a `.` punctuation mark, or "STAR" instead of `★`. This bug appears whenever a prompt asks for a tagline bar. **Every template with a tagline MUST include this block verbatim:**

```
⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · |) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, SEMICOLON, MIDDLE-DOT, PIPE).
• Symbol characters (★ → ◆ › ▼) must render as the actual unicode glyph, NEVER as the spelled-out word (STAR, ARROW, DIAMOND, QUOTE, TRIANGLE).
• Render every dot as a small square pixel or punctuation glyph, not as letters.
• Avoid any duplicate or stuttered words ("PERIOD PERIOD", "STAR STAR", etc.).
```

**Affects:** Cluster A (bottom tagline), Cluster B (middle-dot separators), Cluster C (period/pipe/star separators), Cluster D1 (`✦` callout), Cluster D2 (terminal `zsh$` line), Cluster E (italic editorial tagline). Basically every cluster.

# The 90-second self-audit (updated)

After generating, ask yourself:
1. Does the background look pure black or warm charcoal? (charcoal default; pure `#000` OK for B/E)
2. Is there at least one orange element? (must be — and the right hex for the cluster?)
3. Are the section labels in the right case for this cluster? (A/B/D=lowercase body, C=ALL CAPS, E=sentence case)
4. Are bullets `→` or `›` or `·`? (must NOT be `•`)
5. Is the bottom tagline in the right format for this cluster? (A/B=lowercase manifesto, C=ALL CAPS, E=italic serif)
6. Does the handle appear bottom-right? (must)
7. Are there gradients in body grid areas? (must not — only allowed in hero/canvas zones)
8. Are there rounded corners outside Cluster B/D step cards? (must not)
9. Are Cluster A panels using `◆` diamond + `›` bullets + "what runs here:" ritual? (should — these are the signatures)
10. Does the orange match the cluster (Cluster C → `#F26B1F` / Cluster B → `#B8541F` / Cluster E → `#FC4A2B`)?
11. Did the prompt include the shared text-rules block (PERIOD/STAR forbidden)? (must — see canonical block above)

If you answer "no" to any required or "yes" to any forbidden — regenerate.
