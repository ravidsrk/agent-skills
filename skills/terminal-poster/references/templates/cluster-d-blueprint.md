# Cluster D — Blueprint / Process Poster

**Use case:** Step-by-step tutorial, multi-stage process, "the playbook", or premium "content-in-a-terminal-window" treatment.

> ⚠️ **Audit update (May 24, 2026):** The previous version of this template described a single "dashed orange step pipeline" pattern. **That only matched 1 of 2 source images.** Cluster D actually has TWO sub-variants. Pick whichever matches the topic.

# Two sub-templates — pick one before generating

## 🔴 D1 — Step Pipeline (brand-book / playbook style)
Used by Shann: "10-page brand book → on-brand design machine" (2053844327554801672).

- 6 numbered green-bordered step cards in a horizontal row
- macOS traffic-light dots (red/yellow/green) top-left — REQUIRED window chrome
- **Phosphor green `#A8E060` is the primary accent** (NOT orange)
- Pixel-bitmap headline at top
- Dashed-border framing on each step card
- Bottom: `✦` star-callout with manifesto
- Optional: 2×4 "WHAT'S INSIDE" card grid below the pipeline

## 🟡 D2 — Terminal-Window Mockup (HTML-gates / premium style)
Used by Shann: "where the HTML gate fits in my content system" (2054134844096172356).

- ENTIRE content is wrapped in a fake terminal/editor window
- macOS traffic-light dots top-left of the window chrome — REQUIRED
- The OUTER canvas (outside the window) is a **painterly mossy/textured field** — yes, painterly is allowed here
- Pure ASCII boxes inside the window (no step pipeline)
- Bottom of inner window: `zsh prompt` line for terminal realism
- Strict monochrome inside the window — no accent color, just `#EAEAEA` on `#0E0E0E`

---

## D1 Prompt

### Placeholders to fill
- `[TITLE]` — short pixel-bitmap headline
- `[SUBTITLE]` — one-line description in green monospace
- `[N]` — number of steps (recommend 4-7)
- For each step: `[STEP NAME]`, `[ICON CONCEPT]`, `[2 LINES BODY]`
- `[BOTTOM MANIFESTO]` — for `✦` callout
- `[HANDLE]`

Spec keys (what `scripts/make-poster.sh` reads from a Cluster D1 YAML): `title`, `subtitle`, `bottom_manifesto`, `handle`, `steps[].name`, `steps[].icon`, `steps[].body`. The `[1]`/`[2]` numeric badge is auto-generated from list position.

```
A vertical infographic poster, portrait 3:4 aspect ratio. Premium dev-playbook / technical blueprint aesthetic.

CANVAS: warm dark charcoal #0D0D0D with a very subtle dotted blueprint grid pattern at 5% opacity. Top-left of the canvas: three macOS-style traffic-light circles (red, yellow, green) as window chrome — REQUIRED. They sit just above the title.

FOREGROUND: bone off-white #EAEAEA primary, **phosphor green #A8E060 as the primary accent** (NOT orange). Optional secondary: muted tan #A89680 for captions.

TITLE at top in chunky Press Start 2P / VT323 pixel-bitmap style:
  "[TITLE]"
in phosphor green #A8E060. Below it, a smaller subtitle in green monospace italic:
  "[SUBTITLE]"

Below the title, a horizontal row of [N] step cards connected by long thin dashed green arrows. Each step card is a rectangle outlined with a **thin DASHED green border** (NOT solid, NOT rounded). Inside each card:
  - A single line-art icon at the top (white #EAEAEA, ~2px stroke, Lucide style): [ICON CONCEPT]
  - A numbered label inside square brackets in green: [1], [2], [3], etc.
  - The step name in ALL CAPS cream sans-serif
  - 2 lines of monospace body in muted tan below

Between steps: a long thin dashed green arrow `───── ▶` pointing right.

Step contents (left to right):
  [1] [STEP 1 NAME] — icon: [ICON 1] — "[2 LINES BODY 1]"
  [2] [STEP 2 NAME] — icon: [ICON 2] — "[2 LINES BODY 2]"
  [3] [STEP 3 NAME] — icon: [ICON 3] — "[2 LINES BODY 3]"
  [4] [STEP 4 NAME] — icon: [ICON 4] — "[2 LINES BODY 4]"
  (etc.)

OPTIONAL — below the step pipeline: a 2×4 grid of small "WHAT'S INSIDE" cards listing component bullets. Each card has the same dashed-green border treatment.

Bottom: a single horizontal manifesto callout prefixed with ✦ star, in lowercase manifesto style:
  "✦ [BOTTOM MANIFESTO]"
with "[HANDLE]" right-aligned in muted tan below it.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; ·) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, MIDDLE-DOT).
• Symbol characters (✦ ★ → ◆ ▶) must render as the actual unicode glyph, NEVER as the spelled-out word (STAR, ARROW, DIAMOND, TRIANGLE). Render `✦` as the literal six-point-star character — not the letters "STAR".
• Avoid any duplicate or stuttered words.

Optional bottom-right corner: a small pixel-art robot mascot watching the pipeline (square head, two glowing rectangular green eyes).

Aesthetic: technical manual + engineer's lab notebook + macOS terminal-app screenshot + 1990s computer documentation. Sharp, info-dense, no painterly elements. Flat geometric icons only. Phosphor-green dominant. The macOS traffic-light dots are a signature — never omit them.
```

---

## D2 Prompt

### Placeholders to fill
- `[CONTENT TITLE]` — what's inside the terminal window
- `[N]` — number of ASCII panels inside the window (recommend 3-5)
- For each panel: `[LABEL]`, `[SUBJECT]`, `[PROSE]`, `[ITEMS]`
- `[ZSH PROMPT]` — terminal bottom line, e.g. `~/content-system $ ./gate.sh`
- `[BOTTOM TAGLINE]`
- `[HANDLE]`

Spec keys (what `scripts/make-poster.sh` reads from a Cluster D2 YAML): `content_title`, `zsh_prompt`, `bottom_tagline`, `handle`, `panels[].label`, `panels[].subject`, `panels[].prose`, `panels[].items`.

```
A vertical infographic poster, portrait 3:4 aspect ratio. Premium "content-in-a-terminal-window" treatment.

OUTER CANVAS: a painterly, low-saturation textured field — like a moss-covered stone wall, or a vintage parchment, or a dark forest floor. Painterly is OK and intended for the canvas only. Muted earthy palette — sage green, charcoal, ochre. This canvas frames the entire image and bleeds to the edges.

FLOATING TERMINAL WINDOW (centered, ~80% width, ~85% height): A fake terminal/editor window with these elements:
  - Window chrome at top: gray titlebar #2A2A2A with three macOS traffic-light circles top-left (red #FF5F57, yellow #FFBD2E, green #28C840). Center of titlebar: small monospace text "[CONTENT TITLE]" in muted tan.
  - Inner background: warm charcoal #0E0E0E.
  - Inside the window: strict monochrome ASCII content. Bone #EAEAEA on charcoal. Single monospace font (Berkeley Mono / JetBrains Mono / IBM Plex Mono style).

INNER CONTENT (inside the floating window):
Title line at top: lowercase, e.g. "the html gate in my content system" — underlined with a thin dashed rule.

Below, [N] stacked rectangular panels drawn with thin Unicode box-drawing characters (┌ ─ ┐ │ └ ┘). Each panel has its label inset into the top border:
┌─ [LABEL] ◆ [SUBJECT] ─────────────────┐
Inside each panel: lowercase prose + the `›` quote-bullet list pattern + the "what runs here:" ritual line.

At the very bottom of the inner window: a faux terminal prompt line:
  $ [ZSH PROMPT]

Bottom of the OUTER canvas (below the floating window): a single lowercase manifesto tagline centered in monospace cream:
  "[BOTTOM TAGLINE]"
with "[HANDLE]" right-aligned in muted tan below it.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · $) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, DOLLAR-SIGN). The `$` in the zsh prompt must render as the literal `$` character.
• Symbol characters (◆ › ▼ →) must render as the actual unicode glyph, NEVER as the spelled-out word (DIAMOND, QUOTE, TRIANGLE, ARROW).
• Avoid any duplicate or stuttered words.

Aesthetic: a screenshot of a terminal window pinned over a painterly Studio Ghibli forest scene. The contrast between the FLAT monochrome inside and the PAINTERLY canvas outside is the whole point. The window chrome makes it feel like "this is the actual content, the canvas is the vibe".
```

---

## When to choose D1 vs D2

| | D1 Step Pipeline | D2 Terminal-Window Mockup |
|---|---|---|
| Topic shape | Sequential / "do X, then Y" | Single concept / "here's the rule" |
| Reading direction | Left → right | Top → bottom inside window |
| Primary accent | Phosphor green | Pure monochrome (no accent) |
| Hero | Pixel headline + step cards | The fake window IS the hero |
| Painterly canvas | No | YES (this is what makes D2 premium) |
| Best for | Playbooks, tutorials, "5 steps to X" | "Why HTML > Markdown", premium thought-pieces |

## When to choose Cluster D over Cluster A

- Topic is **temporal / sequential** (D1) — Cluster A reads top-to-bottom hierarchical, D1 reads left-to-right pipeline
- Topic needs **premium / contemplative framing** (D2) — Cluster A is brutalist, D2 is brutalist-inside-pretty
- Audience is **less hackercore** — Cluster A is `man` page, Cluster D is published-article

## Known failure modes

🟡 **Model forgets macOS traffic-light dots** — explicit in the prompt, but sometimes drops. Worth a regeneration if missing.
🟡 **D2 outer canvas drifts too photoreal** — say "painterly low-saturation, Studio Ghibli / oil paint feel" rather than just "textured".
🟡 **D1 with orange instead of green** — the model defaults to orange because of the "Hermes orange" rule elsewhere. Override explicitly: "phosphor green #A8E060 is the PRIMARY accent — NOT orange."
🟡 **Without text-rules block** — model may spell out STAR or PERIOD in tagline. Both D1 and D2 prompts above include the block.

## Reference Shann images (Cluster D canonical)
- D1: `images/2053844327554801672.png` — "10-page brand book → on-brand design machine"
- D2: `images/2054134844096172356.png` — "where the HTML gate fits in my content system"
