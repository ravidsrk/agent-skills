# Cluster B — Color-Coded Dark Infographic

**Use case:** Leveled comparison or maturity model (L1/L2/L3/L4), "X ways to do Y", phased rollout, before/after.

**Look:** Inter-family sans-serif (NOT pixel-bitmap), dark bg, each level/section gets its own semantic color. Cleaner and more corporate than Cluster C.

> ⚠️ **Audit update (May 24, 2026):**
> - Orange in Cluster B is usually **muted rust `#B8541F`**, not vivid Hermes orange `#F26B1F` (Cluster C's orange).
> - Tagline is **lowercase middle-dot separated** — NOT ALL CAPS period-separated (that's Cluster C).
> - Optional motif: **neon brain illustrations** per department/level (from "Hermes Agent company visualized").

---

## Placeholders to fill

- `[TITLE]` — concise lowercase title
- `[SUBTITLE]` — secondary line in muted tan
- `[N]` — number of levels/sections (recommend 3-5)
- For each level: `[LABEL]` (e.g. L1), `[NAME]` (e.g. HEROIC), `[ONE-LINER]`, `[3-5 BULLET POINTS]`. The accent color is derived from `[LABEL]` (L1 → amber, L2 → teal, L3 → magenta, L4 → rust, L5 → gray — see the canonical Cluster B palette in `references/design-dna.md`).
- `[BOTTOM TAGLINE]` — lowercase, middle-dot separated
- `[HANDLE]`

Spec keys (what `scripts/make-poster.sh` reads from a Cluster B YAML): `title`, `subtitle`, `bottom_tagline`, `handle`, `levels[].label`, `levels[].name`, `levels[].oneliner`, `levels[].bullets`.

## Prompt

```
A vertical Twitter/X infographic poster, portrait 2:3 aspect ratio. Modern dark-mode infographic, clean editorial layout.

BACKGROUND: pure #000 OR warm dark charcoal #0E0E0E (both are valid for Cluster B). Very subtle horizontal gradient sections allowed for brightness variation only — not colored.
FOREGROUND: bone off-white #EAEAEA for primary text.

Font: clean modern sans-serif (Inter / Geist / IBM Plex Sans family), regular and semibold weights. NOT a pixel-bitmap font. NOT monospace.

Layout: a vertical "spine" on the left side with stacked colored badges showing level names (L1, L2, L3, L4 etc). To the right of each badge: a card containing the level content. Cards have a thin 1px border in the level's accent color and 8px rounded corners.

Title at top:
  "[TITLE]"
in lowercase Inter semibold. Subtitle line below in muted tan: "[SUBTITLE]"

Then [N] stacked level rows, top to bottom. Each row:
  Left: a colored badge with "L[N]" in white sans-serif on a filled rectangle in the level's accent color (radius 4px).
  Right: a card with
    - Header: "[NAME]" in the same accent color, ALL CAPS, letter-spaced
    - One-liner: "[ONE-LINER]" in cream sans-serif, regular weight
    - Bullets: 3-5 items, each prefixed with → arrow in the accent color, body in muted tan

Cluster B accent palette — pick ONE color per level (semantic, not all-orange).
This is the canonical ramp; do not drift. Also documented in
`references/design-dna.md` "Cluster B palette":
  L1: amber   #FFC857  (kickoff / foundation)
  L2: teal    #00D9D9  (technical / build)
  L3: magenta #B57FFF  (strategy / brain)
  L4: rust    #B8541F  (operations / sales — NOT vivid Hermes orange #F26B1F)
  L5: gray    #A89680  (admin / maintenance)

Between rows: a 1px thin dashed orange vertical line on the spine (using muted rust #B8541F, NOT vivid orange), connecting consecutive badges.

OPTIONAL motif — neon brain illustrations per level: a small 2-color line illustration of a glowing brain shape next to each card, tinted in that level's accent color. Used in "Hermes Agent company visualized" — gives the poster a sci-fi-anatomy feel without breaking the corporate-clean aesthetic.

Bottom: a single LOWERCASE manifesto tagline centered, with phrases separated by `·` middle-dots (NOT periods, NOT ALL CAPS):
  "[BOTTOM TAGLINE phrase 1] · [phrase 2] · [phrase 3]"
with "[HANDLE]" right-aligned below in muted tan.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · |) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, SEMICOLON, MIDDLE-DOT, PIPE). Render every `·` as the actual middle-dot character.
• Avoid any duplicate or stuttered words ("MIDDLE-DOT MIDDLE-DOT" etc.).

Aesthetic: clean Linear-app docs page meets developer-tools landing page. No icons (or very minimal monoline icons), no illustrations except optional neon brains. Flat, sharp, info-dense. 8px rounded corners on cards but EVERYTHING ELSE flat geometric.
```

## Cluster B signature checklist (audit-derived)

✅ Semantic per-level palette (NOT all-orange) — amber, teal, purple, rust, gray
✅ Muted rust `#B8541F` instead of vivid `#F26B1F`
✅ Inter / Geist sans-serif (NOT monospace, NOT pixel)
✅ L1/L2/L3/L4 spine of colored badges
✅ Lowercase middle-dot tagline (NOT ALL CAPS period-separated)
✅ 8px rounded corners on cards (only place rounded corners are OK)

🟡 Optional: neon brain illustrations per level

## When to choose this over Cluster A or C

- Topic has explicit levels/phases (Cluster A handles flat hierarchies better)
- Audience is more enterprise / less hackercore than Cluster C
- You want readability over viral aesthetic

## Reference Shann images (Cluster B canonical)

- `2055059408305168691` — "Hermes Agent company visualized" (lime/cyan/magenta + orange in Sales)
- `2057597341251899403` — "10 first marketing tasks"
- `2057552450794745893` — "every company should be building infrastructure"
