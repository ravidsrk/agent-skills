# Cluster C — Cyborg / Cyberpunk Hero Poster

**🔴 THE VIRAL VERSION.** Use this for feature launches, "X changed how I work" hooks, big announcements. Drives the highest engagement on X.

**Use case:** Feature launch, viral hook, brand-name reveal, "this changed everything" moment.

# Two hero modes — pick one before generating

## 🔴 Mode C1 — PAINTERLY HERO (the viral one)
Used by Shann: gBrain, Control Room, Skill Bundles Ship, xurl (4/6 of his Cluster C posts).

- Painterly cyborg portrait OR illustrated control-room/cockpit scene
- Warm orange + amber painted comic-book style
- Dramatic chiaroscuro + orange rim lighting
- Painterly is OK in the hero zone — just keep it flat-rendered (no photoreal textures)
- Follow the 5 composition rules below (rule of thirds, no halo, three-quarter rear, etc.)

## 🟡 Mode C2 — FLAT PIXEL HERO
Used by Shann: "Ultimate Hermes Agent Army", "4 levels neon variant" (2/6 of his Cluster C posts).

- Flat pixel-art scene with visible square pixels
- No painterly shading
- Pure pixel-art game-asset style
- Good when topic is whimsical / less serious

**If unsure → use Mode C1.** It's the viral one.

---

## Placeholders to fill (both modes)

- `[TOPIC]` — short lowercase name for top-left terminal prompt (e.g. your project's slug)
- `[STATUS]` — short status word for top-left prompt (e.g. "analyst online", "ready", "shipping")
- `[STATUS_2]` — terminal status string for the mirrored top-right prompt (e.g. "uptime 47h", "ready", "ships now"). NOT a version number — the top-right is a SECOND `> sys$` prompt, not a `v1.0.0` stamp.
- `[HANDLE]` — e.g. "@ravidsrk"
- `[EYEBROW]` — small cream kicker line (e.g. "AGENT-NATIVE")
- `[BRAND NAME]` — XL orange (e.g. "MARKETINTELL")
- `[SUBTITLE]` — medium green (e.g. "THE AI ANALYST DESK")
- `[HERO SUBJECT]` — see mode-specific guidance in each prompt
- For each of 6 cards: `[HEADER]`, `[ICON]`, `[3 LINES BODY]`
- 3 tagline phrases for the bottom bar
- `[TAGLINE SEPARATOR]` — choose: `.` periods, `|` pipes, or `★` stars

---

## Prompt — Mode C1 (painterly hero, viral)

> 🔴 **The 5 composition rules below** separate a posed magazine-cover hero from a viral lived-in Shann hero. Audited and codified May 24, 2026 (v4 win). The model handles macro-level composition well (rule-of-thirds, no-halo, side-lit, three-quarter-rear, grit) but struggles with micro-detail asks (battle-worn mascot scratches). Use macro rules. Skip micro asks.

```
A vertical dense infographic poster, portrait 2:3 aspect ratio, retro-cyberpunk dev-tools aesthetic.

BACKGROUND: warm dark charcoal #0E0E0E with subtle ambient orange glow seeping in from the top corners. Faint horizontal CRT scanline overlay at low opacity.

PRIMARY ACCENT: vivid Hermes orange #F26B1F.
Secondary accents: phosphor green #A8E060, cyan #00D9D9, magenta #B57FFF, gold #E8C547.
Cream body text #F0E6D2. Muted tan secondary #A89680.

TOP-LEFT CORNER: terminal prompt "> [TOPIC]$ [STATUS]" in green #A8E060 monospace.
TOP-RIGHT CORNER (MIRRORED — second prompt, not a version stamp): "> sys$ [STATUS_2]  [HANDLE]" in muted tan monospace. STATUS_2 examples: "uptime 47h", "ready", "ships now". NO version number — use a terminal status string instead.

HERO ZONE (top ~30%): A PAINTERLY illustration of [HERO SUBJECT, e.g. "a cyborg AI analyst at a trading desk" OR "an illustrated mission-control cockpit"]. Follow these 5 composition rules — they are what separate a viral hero from a posed magazine cover:

🔴 RULE 1 — CAMERA POSITION: Tight CHEST-UP shot, camera positioned BEHIND the subject's LEFT shoulder, slightly above. Over-the-shoulder framing. NEVER position the camera in front. NEVER show a frontal face. NEVER make this a wide architectural shot — it must feel intimate, close, like you're standing behind them at 3am.

🔴 RULE 2 — RULE OF THIRDS: Subject's head/shoulder silhouette occupies the LEFT THIRD of the hero zone. The right two-thirds are filled with scene context (CRT monitors, instruments, control surfaces). NEVER center the subject.

🔴 RULE 3 — NO RADIAL HALO: Do NOT render a symmetrical radial halo or sunburst behind the head. Orange light spills FROM the scene context (monitors, screen-glow) onto the subject's profile from the RIGHT side — making the back of the head/shoulder half-lit in orange rim light, half in deep shadow. The light source is the scene. Asymmetric side-light only.

🔴 RULE 4 — THREE-QUARTER REAR VIEW: We see the subject from THREE-QUARTER REAR — back of head, side of neck, one shoulder forward. Suggest the half-human half-cyborg detailing (glowing neck filaments, scuffed armor edge) but do NOT showcase the face.

🔴 RULE 5 — LIVED-IN GRIT: Heavy atmosphere — dust motes in orange light beams, scratched monitor bezels, frayed cables snaking across the desk, half-empty coffee cup with steam, sticky notes peeling off a monitor edge, scattered handwritten papers, mug ring stains on the desk. 3am deep-work mood.

Style: painted comic-book / sci-fi concept art with strong orange RIM lighting (from the side, not behind the head), dramatic chiaroscuro, hand-painted brush texture, atmospheric haze, painterly grit. Blade Runner 2049 night scene meets a graphic novel mid-action panel. NOT a magazine hero shot. NOT centered. NOT haloed. Keep the painting flat-rendered (no photoreal textures), like a high-end comic book or Pip-Boy interface.

TITLE (just below hero): stacked 3-line pixel-bitmap headline in chunky Press Start 2P / VT323 style with clearly visible square pixels:
  Line 1 (small, cream #F0E6D2): "[EYEBROW]"
  Line 2 (XL, orange #F26B1F): "[BRAND NAME]"
  Line 3 (medium, green #A8E060): "[SUBTITLE]"

BODY GRID (middle 45-50%): EXACTLY a 3 columns × 2 rows = 6 cards. Identical width and height. Each card has a 1px sharp-cornered border in its accent color, a small all-caps mono header in the same accent color, and 3 lines of monospace body text. Each card has a line-art OR chunky pixel-art icon in the accent color (~2px stroke). CARDS ARE FLAT — no painterly, no shadows, no gradients inside cards. (Painterly is allowed ONLY in the hero zone above.)

Top-left of each card: a filled orange square badge with white numeral inside square brackets:
  Card 1: [1] orange border — "[HEADER 1]" — icon: [ICON 1] — "[3 LINES BODY 1]"
  Card 2: [2] green border — "[HEADER 2]" — icon: [ICON 2] — "[3 LINES BODY 2]"
  Card 3: [3] cyan border — "[HEADER 3]" — icon: [ICON 3] — "[3 LINES BODY 3]"
  Card 4: [4] magenta border — "[HEADER 4]" — icon: [ICON 4] — "[3 LINES BODY 4]"
  Card 5: [5] gold border — "[HEADER 5]" — icon: [ICON 5] — "[3 LINES BODY 5]"
  Card 6: [6] orange border — "[HEADER 6]" — icon: [ICON 6] — "[3 LINES BODY 6]"

Between rows: a thin orange arrow chain `→ → →` showing flow.

BOTTOM TAGLINE BAR (full width, last ~8%): A solid orange #F26B1F band. Inside it, ALL CAPS letter-spaced cream-colored text — the tagline STRING contains ONLY the three phrases (no token placeholders). Choose ONE separator style:
  • Period style: "[TAGLINE 1].  [TAGLINE 2].  [TAGLINE 3]."
  • Pipe style:   "[TAGLINE 1]  |  [TAGLINE 2]  |  [TAGLINE 3]"
  • Star style:   "★ [TAGLINE 1]   ★ [TAGLINE 2]   ★ [TAGLINE 3]"

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• The word "PERIOD" must NEVER appear in the tagline. Use a literal "." punctuation mark, not the spelled-out word.
• Each sentence ends with a single period character "." — not the word PERIOD.
• Render the dot as a small square pixel, not as letters.
• Avoid any duplicate or stuttered words.
• The bar must contain ONLY the three phrases and the robot icon — no labels, no bracketed tokens, no words like "Tagline" or "Mascot".

CENTERED on the tagline bar, between the phrases, sits a LARGE prominent pixel-art robot icon as a SEPARATE GRAPHIC (not text, not a token in the string) — square head, two glowing rectangular orange eyes, two tiny antenna nubs on top, no body. Sized at ~14% of the tagline bar height so it reads as a co-star, NOT a tiny accessory. Render it CLEAN, BOLD, and ICONIC with crisp 8-bit pixel edges. Do NOT attempt subtle damage / scratches / dents / bent antennae — the model handles "clean iconic" well and fails at "weathered detail". Skip the damage asks.

Overall style references: hacker zine, Bloomberg Terminal, Pip-Boy interface, outrun synthwave restraint, 1990s computer manual diagrams. Hero painterly + body cards flat + chrome ENGINEERED. Like Pip-Boy meets graphic novel.
```

---

## Prompt — Mode C2 (flat pixel hero)

Use this when the topic is whimsical or you want a lighter feel. Full prompt block below — copy-paste ready, no mental splicing required.

```
A vertical dense infographic poster, portrait 2:3 aspect ratio, retro-cyberpunk dev-tools aesthetic.

BACKGROUND: warm dark charcoal #0E0E0E with subtle ambient orange glow seeping in from the top corners. Faint horizontal CRT scanline overlay at low opacity.

PRIMARY ACCENT: vivid Hermes orange #F26B1F.
Secondary accents: phosphor green #A8E060, cyan #00D9D9, magenta #B57FFF, gold #E8C547.
Cream body text #F0E6D2. Muted tan secondary #A89680.

TOP-LEFT CORNER: terminal prompt "> [TOPIC]$ [STATUS]" in green #A8E060 monospace.
TOP-RIGHT CORNER (MIRRORED — second prompt, not a version stamp): "> sys$ [STATUS_2]  [HANDLE]" in muted tan monospace.

HERO ZONE (top ~22%, keep small): A FLAT PIXEL-ART scene of [HERO SUBJECT, e.g. "three vintage CRT monitors in a row showing a candlestick chart, a node graph, and an ASCII table"]. Behind it, a stepped pixel-art [BACKGROUND ELEMENT, e.g. "brain silhouette"] outlined in orange — must look bitmap with visible square pixels, not smooth curves. Pure pixel-art game-asset style. NO painterly. NO smooth gradients. NO radial glow.

TITLE (just below hero): stacked 3-line pixel-bitmap headline in chunky Press Start 2P / VT323 style with clearly visible square pixels:
  Line 1 (small, cream #F0E6D2): "[EYEBROW]"
  Line 2 (XL, orange #F26B1F): "[BRAND NAME]"
  Line 3 (medium, green #A8E060): "[SUBTITLE]"

BODY GRID (middle 55%): EXACTLY a 3 columns × 2 rows = 6 cards. Identical width and height. Each card has a 1px sharp-cornered border in its accent color, a small all-caps mono header in the same accent color, and 3 lines of monospace body text. Each card has a chunky pixel-art icon (visible square pixels, ~2px stroke).

Top-left of each card: a filled orange square badge with white numeral inside square brackets:
  Card 1: [1] orange border — "[HEADER 1]" — pixel icon: [ICON 1] — "[3 LINES BODY 1]"
  Card 2: [2] green border — "[HEADER 2]" — pixel icon: [ICON 2] — "[3 LINES BODY 2]"
  Card 3: [3] cyan border — "[HEADER 3]" — pixel icon: [ICON 3] — "[3 LINES BODY 3]"
  Card 4: [4] magenta border — "[HEADER 4]" — pixel icon: [ICON 4] — "[3 LINES BODY 4]"
  Card 5: [5] gold border — "[HEADER 5]" — pixel icon: [ICON 5] — "[3 LINES BODY 5]"
  Card 6: [6] orange border — "[HEADER 6]" — pixel icon: [ICON 6] — "[3 LINES BODY 6]"

Between rows: a thin orange arrow chain `→ → →` showing flow.

BOTTOM TAGLINE BAR (full width, last ~8%): A solid orange #F26B1F band. Inside it, ALL CAPS letter-spaced cream-colored text — the tagline STRING contains ONLY the three phrases (no token placeholders). Choose ONE separator style:
  • Period style: "[TAGLINE 1].  [TAGLINE 2].  [TAGLINE 3]."
  • Pipe style:   "[TAGLINE 1]  |  [TAGLINE 2]  |  [TAGLINE 3]"
  • Star style:   "★ [TAGLINE 1]   ★ [TAGLINE 2]   ★ [TAGLINE 3]"

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• The word "PERIOD" must NEVER appear in the tagline. Use a literal "." punctuation mark, not the spelled-out word.
• Each sentence ends with a single period character "." — not the word PERIOD.
• Render the dot as a small square pixel, not as letters.
• Avoid any duplicate or stuttered words.
• The bar must contain ONLY the three phrases and the robot icon — no labels, no bracketed tokens, no words like "Tagline" or "Mascot".

CENTERED on the tagline bar, between the phrases, sits a LARGE pixel-art robot icon as a SEPARATE GRAPHIC (not text, not a token in the string) — square head, two glowing rectangular orange eyes, two tiny antenna nubs on top, no body. Sized at ~14% of the tagline bar height. CLEAN BOLD ICONIC pixel edges. Do NOT ask for damage details.

Overall style references: hacker zine, Bloomberg Terminal, Pip-Boy interface, 8-bit game manual cover. Everything pixel-art and chunky.
```

---

## Optional motifs (audit-discovered)

🟡 **Stack-equation centerpiece** — A centered `X = Y` declaration on a fake CRT monitor, e.g. `STACK = AGENT + TOOLS + DATA`. Use instead of the body grid when topic is a single equation/formula.

🟡 **Plus-chain equation footer** — Above the tagline bar: `BRAIN + SKILLS + ROUTING = COMPANY`. Reinforces the manifesto.

🟡 **Numbered cross-reference tags** — `#3`, `#7`, `#10` scattered across cards to demonstrate flywheel/non-linear flow (not strictly sequential).

---

## Known failure modes

🔴 **Nano Banana 2 (not Pro)** — produces duplicate cards. Always use Pro.
🔴 **Without "EXACTLY 3 columns × 2 rows"** — produces asymmetric 4+3 layouts.
🔴 **Without the text-rules block** — spells out "PERIOD" in tagline bar.
🔴 **Without the 5 composition rules (Mode C1)** — produces a centered/posed magazine-cover hero with prominent radial halo. This is the #1 Cluster C failure mode.
🟡 **Brand names with short letters** — may get one glyph corrupted.
🟡 **Mode confusion** — if you ask for C1 painterly + C2 pixel-art together, the model picks one randomly. Be explicit which mode.
🟡 **Asking for micro-damage on mascot** — model produces "clean pixel bot" anyway and silently drops the damage details. Don't ask.

📊 **For test results and lessons-learned across 4 iterations, see `references/worked-examples.md`.** Cliff notes: v1 (Mode C1 first try) = 95.6% polish king; v4 (composition canonical) = 90.7% generalizable. The prompt above is v4.
