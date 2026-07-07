#!/usr/bin/env bash
# make-poster.sh — One-command poster generator using the terminal-poster skill.
#
# Usage:
#   make-poster.sh <spec.yaml> <output.png> [--dry-run]
#
# Spec format: see scripts/example-specs/
# Reads a YAML poster spec -> picks the right cluster template -> fills placeholders ->
# runs generate.sh -> writes the image.
#
# --dry-run: skip the OpenRouter API call. Still writes <output>.prompt.txt so
# you can inspect the exact prompt. No credits are burned. This is the
# recommended way to iterate on templates and specs.
#
# Dependencies: yq (for YAML parsing), bash 4+, generate.sh in same dir.
#
# Exit codes:
#   0 = success
#   1 = bad args
#   2 = missing dependency
#   3 = spec parse error
#   4 = generation failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$SKILL_DIR/references/templates"

# --- Args ---
DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: make-poster.sh <spec.yaml> <output.png> [--dry-run]" >&2
      echo "Spec format examples: $SCRIPT_DIR/example-specs/" >&2
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg" >&2
      echo "Usage: make-poster.sh <spec.yaml> <output.png> [--dry-run]" >&2
      exit 1
      ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  echo "Usage: make-poster.sh <spec.yaml> <output.png> [--dry-run]" >&2
  echo "Spec format examples: $SCRIPT_DIR/example-specs/" >&2
  exit 1
fi

SPEC="${POSITIONAL[0]}"
OUTPUT="${POSITIONAL[1]}"

if [ ! -f "$SPEC" ]; then
  echo "ERROR: Spec file not found: $SPEC" >&2
  exit 1
fi

# --- Dependency check ---
if ! command -v yq >/dev/null 2>&1; then
  UNAME_S="$(uname -s)"
  UNAME_M="$(uname -m)"
  case "$UNAME_S" in
    Darwin)
      echo "ERROR: yq not found. On macOS install via Homebrew:" >&2
      echo "         brew install yq" >&2
      exit 2
      ;;
    Linux)
      case "$UNAME_M" in
        x86_64) YQ_BIN="yq_linux_amd64" ;;
        aarch64|arm64) YQ_BIN="yq_linux_arm64" ;;
        *)
          echo "ERROR: yq not found and no auto-installer for arch $UNAME_M." >&2
          echo "         See https://github.com/mikefarah/yq/releases/latest" >&2
          exit 2
          ;;
      esac
      # Prefer /usr/local/bin when writable, otherwise fall back to ~/.local/bin.
      if [ -w /usr/local/bin ] 2>/dev/null; then
        INSTALL_DIR=/usr/local/bin
      else
        INSTALL_DIR="$HOME/.local/bin"
      fi
      mkdir -p "$INSTALL_DIR"
      echo "[make-poster] yq not found; installing $YQ_BIN to $INSTALL_DIR ..." >&2
      curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BIN" \
        -o "$INSTALL_DIR/yq"
      chmod +x "$INSTALL_DIR/yq"
      export PATH="$INSTALL_DIR:$PATH"
      ;;
    *)
      echo "ERROR: yq not found and platform $UNAME_S has no auto-installer." >&2
      echo "         See https://github.com/mikefarah/yq/releases/latest" >&2
      exit 2
      ;;
  esac
fi

# --- Helpers ---
# yq (mikefarah v4+) prints the literal string "null" for missing keys and
# exits 0. Map that back to empty string so absent optional fields don't
# leak the word "null" into the model prompt.
yqr() {
  local v
  v=$(yq -r "$1" "$SPEC" 2>/dev/null || echo "")
  [ "$v" = "null" ] && v=""
  printf '%s' "$v"
}

# --- Parse spec ---
CLUSTER=$(yqr '.cluster')
MODE=$(yqr '.mode')  # optional, e.g. c1/c2/d1/d2

if [ -z "$CLUSTER" ]; then
  echo "❌ Spec missing required field: cluster (one of: a, b, c, d, e)" >&2
  exit 3
fi

CLUSTER=$(printf '%s' "$CLUSTER" | tr '[:upper:]' '[:lower:]')
MODE=$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]')

echo "[make-poster] cluster=$CLUSTER mode=${MODE:-default} spec=$SPEC dry_run=$DRY_RUN"

# --- Build prompt by dispatching to cluster handler ---
PROMPT_FILE=$(mktemp -t poster-prompt.XXXXXX)

case "$CLUSTER" in
  a)
    # Cluster A — ASCII Terminal
    TITLE=$(yqr '.title')
    TAGLINE=$(yqr '.bottom_tagline')
    HANDLE=$(yqr '.handle')
    PANELS_COUNT=$(yq -r '.panels | length' "$SPEC")

    cat > "$PROMPT_FILE" <<EOF
A vertical Twitter/X infographic poster, portrait 2:3 aspect ratio.
Two-tone monochrome: warm near-black background #0E0E0E, bone off-white foreground #EAEAEA. Zero accent colors. No gradients, no shadows, no rounded corners.

Render the entire image in a single monospace font (Berkeley Mono / JetBrains Mono / IBM Plex Mono style), regular weight, fixed character grid. Lowercase body text, ALL CAPS section labels inline within panel borders.

Title at top:
  "$TITLE"
underlined by a single thin horizontal rule of dashes spanning the page width.

Below, $PANELS_COUNT stacked rectangular panels drawn with thin Unicode box-drawing characters (┌ ─ ┐ │ └ ┘). Each panel has its label inset into the top border in the form "label: subject ◆ panel-tagline". Render the panel headers EXACTLY as listed under "Panel contents" below — never render placeholder tokens or square brackets in headers.

The ◆ DIAMOND SEPARATOR between subject and panel-tagline is REQUIRED — it is THE Cluster A signature. Always include it.

DO NOT use [1] or [2] bracketed numerals — those are Cluster C convention. Cluster A uses inline LAYER N: / LEVEL N: / STAGE N: labels in the top border.

Inside each panel:
  1. A small ASCII flow diagram with filled triangular arrowheads (X ──▶ Y style)
  2. A 2-line lowercase prose description
  3. The RITUAL line in lowercase: "what runs here:" (this exact phrase, always present)
  4. A 4-item example list, each prefixed with the › right-angle quote character — NOT → arrows, NOT • bullets. The › is the canonical Cluster A list bullet.

Panel contents (in order, top to bottom):

EOF

    # Loop panels
    for i in $(seq 0 $((PANELS_COUNT-1))); do
      LABEL=$(yqr ".panels[$i].label")
      SUBJECT=$(yqr ".panels[$i].subject")
      PANEL_TAGLINE=$(yqr ".panels[$i].tagline")
      FLOW=$(yqr ".panels[$i].flow")
      PROSE=$(yqr ".panels[$i].prose")

      cat >> "$PROMPT_FILE" <<EOF
┌─ $LABEL: $SUBJECT ◆ $PANEL_TAGLINE ──────────────────┐
ASCII flow: $FLOW
prose: $PROSE
what runs here:
EOF
      # Loop items
      ITEMS_COUNT=$(yq -r ".panels[$i].items | length" "$SPEC")
      for j in $(seq 0 $((ITEMS_COUNT-1))); do
        ITEM=$(yqr ".panels[$i].items[$j]")
        echo "  › $ITEM" >> "$PROMPT_FILE"
      done
      echo "" >> "$PROMPT_FILE"
    done

    cat >> "$PROMPT_FILE" <<EOF

Between panels: a single │ followed by ▼ as flow connector (vertical pipe with downward triangle).

Bottom: a single LOWERCASE manifesto tagline centered:
  "$TAGLINE"
with "$HANDLE" right-aligned below.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; ·) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, MIDDLE-DOT).
• Symbol characters (◆ › ▼ → ─ ┌ ┐ │ └ ┘) must render as the actual unicode glyph, NEVER as the spelled-out word. The ◆ must be a literal diamond, not "DIAMOND".
• Avoid any duplicate or stuttered words.

The aesthetic is a \`man\` page rendered as wall art — engineer-poet zine, terminal-core, brutalist minimalism. No icons, no illustrations, no emoji, no colors other than off-white on near-black.
EOF
    ;;

  c)
    # Cluster C — Cyborg Hero (default Mode C1 painterly)
    SUB_MODE="${MODE:-c1}"
    TOPIC=$(yqr '.topic')
    STATUS=$(yqr '.status')
    STATUS_2=$(yqr '.status_2')
    HANDLE=$(yqr '.handle')
    EYEBROW=$(yqr '.eyebrow')
    BRAND=$(yqr '.brand')
    SUBTITLE=$(yqr '.subtitle')
    HERO_SUBJECT=$(yqr '.hero_subject')
    TAGLINE_SEP=$(yqr '.tagline_separator')
    TAGLINE_SEP="${TAGLINE_SEP:-star}"  # default to ★

    cat > "$PROMPT_FILE" <<EOF
A vertical dense infographic poster, portrait 2:3 aspect ratio, retro-cyberpunk dev-tools aesthetic.

BACKGROUND: warm dark charcoal #0E0E0E with subtle ambient orange glow seeping in from the top corners. Faint horizontal CRT scanline overlay at low opacity.

PRIMARY ACCENT: vivid Hermes orange #F26B1F.
Secondary accents: phosphor green #A8E060, cyan #00D9D9, magenta #B57FFF, gold #E8C547.
Cream body text #F0E6D2. Muted tan secondary #A89680.

TOP-LEFT CORNER: terminal prompt "> $TOPIC\$ $STATUS" in green #A8E060 monospace.
TOP-RIGHT CORNER (MIRRORED — second prompt, not a version stamp): "> sys\$ $STATUS_2  $HANDLE" in muted tan monospace.

EOF

    if [ "$SUB_MODE" = "c2" ]; then
      # Hero subject is expected to be a full scene description ("a flat 8-bit
      # pixel-art scene of ..."). Do NOT prepend a wrapper sentence here or the
      # prompt double-scopes the scene. Style constraints live below.
      cat >> "$PROMPT_FILE" <<EOF
HERO ZONE (top ~22%, keep small): $HERO_SUBJECT

Style constraints for the hero zone: pure flat pixel-art game-asset style, visible square pixels along every edge, 1-bit shading. NO painterly. NO smooth gradients. NO radial glow.

EOF
    else
      # C1 painterly hero with 5 composition rules.
      # hero_subject is expected to be a full scene description.
      cat >> "$PROMPT_FILE" <<EOF
HERO ZONE (top ~30%): $HERO_SUBJECT

Follow these 5 composition rules for the hero zone:

🔴 RULE 1 — CAMERA POSITION: Tight CHEST-UP shot, camera positioned BEHIND the subject's LEFT shoulder, slightly above. Over-the-shoulder framing. NEVER frontal. NEVER wide.

🔴 RULE 2 — RULE OF THIRDS: Subject's head/shoulder at the LEFT THIRD. Scene context fills right two-thirds. NEVER center the subject.

🔴 RULE 3 — NO RADIAL HALO: NO symmetrical halo behind the head. Orange light spills FROM the scene context onto the subject's profile from the RIGHT side — asymmetric side-light only.

🔴 RULE 4 — THREE-QUARTER REAR VIEW: Back of head, side of neck, one shoulder forward. Do NOT showcase the face.

🔴 RULE 5 — LIVED-IN GRIT: dust motes in light beams, scratched monitor bezels, frayed cables, half-empty coffee cup with steam, sticky notes peeling, scattered papers, mug ring stains. 3am deep-work mood.

Style: painted comic-book / sci-fi concept art with strong orange RIM lighting (from the side), dramatic chiaroscuro, hand-painted brush texture, atmospheric haze, painterly grit. Blade Runner 2049 night scene meets a graphic novel mid-action panel. Flat-rendered painting (no photoreal textures).

EOF
    fi

    cat >> "$PROMPT_FILE" <<EOF
TITLE (just below hero): stacked 3-line pixel-bitmap headline in chunky Press Start 2P / VT323 style with clearly visible square pixels:
  Line 1 (small, cream #F0E6D2): "$EYEBROW"
  Line 2 (XL, orange #F26B1F): "$BRAND"
  Line 3 (medium, green #A8E060): "$SUBTITLE"

BODY GRID (middle 45-50%): EXACTLY a 3 columns × 2 rows = 6 cards. Identical width and height. Each card has a 1px sharp-cornered border in its accent color, a small all-caps mono header in the same accent color, and 3 lines of monospace body text. Each card has a line-art OR chunky pixel-art icon in the accent color (~2px stroke). CARDS ARE FLAT — no painterly, no shadows, no gradients inside cards.

Top-left of each card: a filled orange square badge with white numeral inside square brackets:
EOF

    # Loop cards
    CARDS_COUNT=$(yq -r '.cards | length' "$SPEC")
    BORDER_COLORS=(orange green cyan magenta gold orange)
    for i in $(seq 0 $((CARDS_COUNT-1))); do
      HEADER=$(yqr ".cards[$i].header")
      ICON=$(yqr ".cards[$i].icon")
      BODY=$(yqr ".cards[$i].body")
      COLOR="${BORDER_COLORS[$i]}"
      NUM=$((i+1))
      echo "  Card $NUM: [$NUM] $COLOR border — \"$HEADER\" — icon: $ICON — \"$BODY\"" >> "$PROMPT_FILE"
    done

    cat >> "$PROMPT_FILE" <<EOF

Between rows: a thin orange arrow chain \`→ → →\` showing flow.

BOTTOM TAGLINE BAR (full width, last ~8%): A solid orange #F26B1F band. Inside it, ALL CAPS letter-spaced cream-colored text.
EOF

    # Tagline phrases
    PHRASE1=$(yqr '.tagline_phrases[0]')
    PHRASE2=$(yqr '.tagline_phrases[1]')
    PHRASE3=$(yqr '.tagline_phrases[2]')

    case "$TAGLINE_SEP" in
      star)
        echo "The bar's text reads exactly: \"★ $PHRASE1   ★ $PHRASE2   ★ $PHRASE3\"" >> "$PROMPT_FILE"
        ;;
      pipe)
        echo "The bar's text reads exactly: \"$PHRASE1  |  $PHRASE2  |  $PHRASE3\"" >> "$PROMPT_FILE"
        ;;
      period|*)
        echo "The bar's text reads exactly: \"$PHRASE1.  $PHRASE2.  $PHRASE3.\"" >> "$PROMPT_FILE"
        ;;
    esac

    cat >> "$PROMPT_FILE" <<EOF

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · |) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, MIDDLE-DOT, PIPE).
• Symbol characters (★ → ◆ › ▼) must render as the actual unicode glyph, NEVER as the spelled-out word (STAR, ARROW, DIAMOND, QUOTE, TRIANGLE).
• Render every dot as a small square pixel or punctuation glyph, not as letters.
• Avoid any duplicate or stuttered words.

CENTERED on the tagline bar, between the phrases, sits a LARGE prominent pixel-art robot icon (a graphic, not text) — square head, two glowing rectangular orange eyes, two tiny antenna nubs on top, no body. Sized at ~14% of the tagline bar height. CLEAN, BOLD, and ICONIC with crisp 8-bit pixel edges. Do NOT attempt damage details. The bar must contain ONLY the three phrases and the robot icon — no labels, no bracketed tokens, no words like "Tagline" or "Mascot".

Overall style references: hacker zine, Bloomberg Terminal, Pip-Boy interface, 1990s computer manual diagrams. Hero painterly (Mode C1) or flat-pixel (Mode C2) + body cards flat + chrome ENGINEERED.
EOF
    ;;

  b)
    # Cluster B — Color-Coded Levels
    TITLE=$(yqr '.title')
    SUBTITLE=$(yqr '.subtitle')
    TAGLINE=$(yqr '.bottom_tagline')
    HANDLE=$(yqr '.handle')
    LEVELS_COUNT=$(yq -r '.levels | length' "$SPEC")

    cat > "$PROMPT_FILE" <<EOF
A vertical infographic poster, portrait 2:3 aspect ratio. Modern Linear-app docs aesthetic — clean, restrained, slightly editorial.

BACKGROUND: warm dark charcoal #0E0E0E. Subtle 12-column grid hinted at 3% opacity.

FOREGROUND: bone off-white #EAEAEA. Body text in lowercase Inter or Geist sans-serif (NOT monospace, NOT pixel-bitmap). ALL CAPS section labels in letter-spaced Inter.

Per-level semantic palette — use distinct colors per level, NOT all-orange.
Canonical Cluster B palette (also in references/design-dna.md "Cluster B palette"):
  L1 amber   #FFC857
  L2 teal    #00D9D9
  L3 magenta #B57FFF
  L4 rust    #B8541F  (NOT vivid Hermes orange #F26B1F — use the desaturated rust)
  L5 gray    #A89680

TITLE at top in lowercase Inter (NOT pixel-bitmap):
  "$TITLE"
Below it, a smaller subtitle in italic muted tan:
  "$SUBTITLE"

Below the title, a VERTICAL SPINE of $LEVELS_COUNT level cards stacked top-to-bottom. Each level card has:
  - A LEFT-side colored badge in its accent color: L1 / L2 / L3 / L4 in ALL CAPS letter-spaced
  - The level name in ALL CAPS Inter letter-spaced, accent color
  - A short ONE-LINER in lowercase Inter italic, muted tan
  - A 3-5 bullet list using \`→\` arrow bullets in the level's accent color
  - 1px solid border in the level's accent color, with 8px rounded corners (Cluster B is the only cluster with rounded corners)
  - Subtle accent-tinted background fill at ~5% opacity inside the card

Levels (top to bottom):

EOF

    # Loop levels
    for i in $(seq 0 $((LEVELS_COUNT-1))); do
      LABEL=$(yqr ".levels[$i].label")
      NAME=$(yqr ".levels[$i].name")
      ONELINER=$(yqr ".levels[$i].oneliner")

      cat >> "$PROMPT_FILE" <<EOF
$LABEL $NAME
  one-liner: $ONELINER
  bullets:
EOF
      ITEMS_COUNT=$(yq -r ".levels[$i].bullets | length" "$SPEC")
      for j in $(seq 0 $((ITEMS_COUNT-1))); do
        ITEM=$(yqr ".levels[$i].bullets[$j]")
        echo "    → $ITEM" >> "$PROMPT_FILE"
      done
      echo "" >> "$PROMPT_FILE"
    done

    cat >> "$PROMPT_FILE" <<EOF

Bottom: a single LOWERCASE manifesto tagline centered, with phrases separated by \`·\` middle-dots (NOT periods, NOT ALL CAPS):
  "$TAGLINE"
with "$HANDLE" right-aligned below in muted tan.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · |) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, SEMICOLON, MIDDLE-DOT, PIPE). Render every \`·\` as the actual middle-dot character.
• Symbol characters (→ ◆) must render as the actual unicode glyph, NEVER as the spelled-out word (ARROW, DIAMOND).
• Avoid any duplicate or stuttered words.

Aesthetic references: Linear docs, Stripe Press, Vercel marketing. Restrained, editorial, clear hierarchy. NOT terminal/cyberpunk. NOT pixel-bitmap. NOT painterly.
EOF
    ;;

  d)
    # Cluster D — pick D1 (step pipeline) or D2 (terminal-window)
    SUB_MODE="${MODE:-d1}"

    if [ "$SUB_MODE" = "d2" ]; then
      # D2 — Terminal-Window Mockup on painterly canvas
      CONTENT_TITLE=$(yqr '.content_title')
      ZSH_PROMPT=$(yqr '.zsh_prompt')
      TAGLINE=$(yqr '.bottom_tagline')
      HANDLE=$(yqr '.handle')
      PANELS_COUNT=$(yq -r '.panels | length' "$SPEC")

      cat > "$PROMPT_FILE" <<EOF
A vertical infographic poster, portrait 3:4 aspect ratio. Premium "content-in-a-terminal-window" treatment.

OUTER CANVAS: a painterly, low-saturation textured field — like a moss-covered stone wall, or a vintage parchment, or a dark forest floor. Painterly is OK and intended for the canvas only. Muted earthy palette — sage green, charcoal, ochre. This canvas frames the entire image and bleeds to the edges.

FLOATING TERMINAL WINDOW (centered, ~80% width, ~85% height): A fake terminal/editor window with these elements:
  - Window chrome at top: gray titlebar #2A2A2A with three macOS traffic-light circles top-left (red #FF5F57, yellow #FFBD2E, green #28C840). Center of titlebar: small monospace text "$CONTENT_TITLE" in muted tan.
  - Inner background: warm charcoal #0E0E0E.
  - Inside the window: strict monochrome ASCII content. Bone #EAEAEA on charcoal. Single monospace font (Berkeley Mono / JetBrains Mono / IBM Plex Mono style).

INNER CONTENT (inside the floating window):
Title line at top: lowercase, underlined with a thin dashed rule.

Below, $PANELS_COUNT stacked rectangular panels drawn with thin Unicode box-drawing characters (┌ ─ ┐ │ └ ┘). Each panel has its label inset into the top border in the form "label ◆ subject". Render the panel headers EXACTLY as listed under "Panel contents" below — never render placeholder tokens or square brackets in headers.

Inside each panel: lowercase prose + the \`›\` quote-bullet list pattern + the "what runs here:" ritual line.

Panel contents (in order):

EOF

      for i in $(seq 0 $((PANELS_COUNT-1))); do
        LABEL=$(yqr ".panels[$i].label")
        SUBJECT=$(yqr ".panels[$i].subject")
        PROSE=$(yqr ".panels[$i].prose")
        cat >> "$PROMPT_FILE" <<EOF
┌─ $LABEL ◆ $SUBJECT ──────────────────┐
$PROSE
what runs here:
EOF
        ITEMS_COUNT=$(yq -r ".panels[$i].items | length" "$SPEC")
        for j in $(seq 0 $((ITEMS_COUNT-1))); do
          ITEM=$(yqr ".panels[$i].items[$j]")
          echo "  › $ITEM" >> "$PROMPT_FILE"
        done
        echo "" >> "$PROMPT_FILE"
      done

      cat >> "$PROMPT_FILE" <<EOF

At the very bottom of the inner window: a faux terminal prompt line:
  $ZSH_PROMPT

Bottom of the OUTER canvas (below the floating window): a single lowercase manifesto tagline centered in monospace cream:
  "$TAGLINE"
with "$HANDLE" right-aligned in muted tan below it.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; · \$) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, DOLLAR-SIGN). The \$ in the zsh prompt must render as the literal \$ character.
• Symbol characters (◆ › ▼ →) must render as the actual unicode glyph, NEVER as the spelled-out word (DIAMOND, QUOTE, TRIANGLE, ARROW).
• Avoid any duplicate or stuttered words.

Aesthetic: a screenshot of a terminal window pinned over a painterly Studio Ghibli forest scene. The contrast between the FLAT monochrome inside and the PAINTERLY canvas outside is the whole point.
EOF
    else
      # D1 — Step Pipeline (default)
      TITLE=$(yqr '.title')
      SUBTITLE=$(yqr '.subtitle')
      MANIFESTO=$(yqr '.bottom_manifesto')
      HANDLE=$(yqr '.handle')
      STEPS_COUNT=$(yq -r '.steps | length' "$SPEC")

      cat > "$PROMPT_FILE" <<EOF
A vertical infographic poster, portrait 3:4 aspect ratio. Premium dev-playbook / technical blueprint aesthetic.

CANVAS: warm dark charcoal #0D0D0D with a very subtle dotted blueprint grid pattern at 5% opacity. Top-left of the canvas: three macOS-style traffic-light circles (red, yellow, green) as window chrome — REQUIRED. They sit just above the title.

FOREGROUND: bone off-white #EAEAEA primary, **phosphor green #A8E060 as the primary accent** (NOT orange, NOT amber, NOT yellow). Optional secondary: muted tan #A89680 for captions.

TITLE at top in chunky Press Start 2P / VT323 pixel-bitmap style:
  "$TITLE"
in phosphor green #A8E060. Below it, a smaller subtitle in green monospace italic:
  "$SUBTITLE"

Below the title, $STEPS_COUNT step cards laid out as a pipeline (horizontal row if $STEPS_COUNT ≤ 4, otherwise compact 2-row wrap with continuation arrows). Each step card is a rectangle outlined with a **thin DASHED green border** (NOT solid, NOT rounded). Inside each card:
  - A single line-art icon at the top (white #EAEAEA, ~2px stroke, Lucide style)
  - A numbered label inside square brackets in green: [1], [2], [3], etc.
  - The step name in ALL CAPS cream sans-serif
  - 2 lines of monospace body in muted tan below

Between steps: a long thin dashed green arrow \`───── ▶\` pointing right (or down-and-right if wrapping rows).

Step contents (left to right, then wrap):

EOF

      for i in $(seq 0 $((STEPS_COUNT-1))); do
        NAME=$(yqr ".steps[$i].name")
        ICON=$(yqr ".steps[$i].icon")
        BODY=$(yqr ".steps[$i].body")
        NUM=$((i+1))
        echo "  [$NUM] $NAME — icon: $ICON — \"$BODY\"" >> "$PROMPT_FILE"
      done

      cat >> "$PROMPT_FILE" <<EOF

Bottom: a single horizontal manifesto callout prefixed with ✦ star, in lowercase manifesto style:
  "✦ $MANIFESTO"
with "$HANDLE" right-aligned in muted tan below it.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; ·) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, MIDDLE-DOT).
• Symbol characters (✦ ★ → ◆ ▶) must render as the actual unicode glyph, NEVER as the spelled-out word (STAR, ARROW, DIAMOND, TRIANGLE). Render \`✦\` as the literal six-point-star character.
• Avoid any duplicate or stuttered words.

Aesthetic: technical manual + engineer's lab notebook + macOS terminal-app screenshot + 1990s computer documentation. Sharp, info-dense, no painterly elements. Flat geometric icons only. **Phosphor-green dominant — NOT orange.** The macOS traffic-light dots are a signature — never omit them.
EOF
    fi
    ;;

  e)
    # Cluster E — Editorial Brand Book
    BRAND=$(yqr '.brand')
    HERO_TAGLINE=$(yqr '.hero_tagline')
    BOTTOM_TAGLINE=$(yqr '.bottom_tagline')
    HANDLE=$(yqr '.handle')
    PAGES_COUNT=$(yq -r '.pages | length' "$SPEC")

    cat > "$PROMPT_FILE" <<EOF
A vertical infographic poster, portrait 2:3 aspect ratio. High-end editorial brand-book spread aesthetic.

🔴 BACKGROUND: pure DARK CANVAS #0D0D0D — NOT a single cream page. The canvas is the backdrop. Multiple CREAM / OFF-WHITE brand-book PAGES float ON TOP of the dark canvas as a composited spread. The pages themselves are #F5F0E6 cream with subtle paper-grain texture.

LAYOUT: split the composition into LEFT 2/3 and RIGHT 1/3.

LEFT 2/3: A 3×3 grid of $PAGES_COUNT small portrait-orientation page thumbnails arranged like a magazine contact-sheet. Each thumbnail is a cream page floating on the dark canvas, with a 1px hairline border. Each labeled with its section number in Inter caps letter-spaced (e.g. "01 /", "02 /", "03 /").

RIGHT 1/3: ONE enlarged master page at readable scale. This is the hero. It shows:
  - Brand name "$BRAND" in extra-large Instrument Serif (NOT all caps — sentence case with serif elegance)
  - Italic Inter or italic Instrument Serif tagline below: "$HERO_TAGLINE"
  - A banded orange→peach aura/halo gradient behind the headline (stacked light-leak look, NOT smooth radial). Use Bookmark Red #FC4A2B fading to Save Peach #F7A488.
  - Subtle paper-grain texture on the page

ACCENT PALETTE — NOT Hermes orange #F26B1F. Use these editorial colors:
  Bookmark Red #FC4A2B (primary accent)
  Save Peach #F7A488 (secondary)
  Confirm Green #1E8E3E (active state)
  Pitch Black #0D0D0D (canvas)
  Ash Gray #8E8E8E (muted body)

Page contents (left grid, in order):

EOF

    for i in $(seq 0 $((PAGES_COUNT-1))); do
      NUMBER=$(yqr ".pages[$i].number")
      LABEL=$(yqr ".pages[$i].label")
      CONTENT=$(yqr ".pages[$i].content")
      cat >> "$PROMPT_FILE" <<EOF
$NUMBER / $LABEL
  content: $CONTENT
EOF
    done

    cat >> "$PROMPT_FILE" <<EOF

Bottom of canvas (below the spread): a thin horizontal divider line, then a single italic Instrument Serif tagline centered — SENTENCE CASE not all caps:
  "$BOTTOM_TAGLINE"
with "$HANDLE" right-aligned in small caps Inter below.

⚠️ CRITICAL TEXT RULES — read carefully before rendering letters:
• Spell every word completely. Do NOT abbreviate. Do NOT drop letters.
• Punctuation marks (. , : ; — /) must render as actual punctuation glyphs, NEVER as the spelled-out word (PERIOD, COMMA, COLON, EM-DASH, SLASH). The \`/\` in section labels like "01 / BRAND IDEA" must render as a literal slash character.
• Avoid any duplicate or stuttered words.

Aesthetic: a fashion magazine brand book + a Pentagram identity reveal + a Saturday Evening Post spread. Warm, contemplative, editorial. NOT terminal. NOT cyberpunk. NOT pixel-bitmap. Sentence-case throughout, italic editorial tagline (breaks the ALL-CAPS rule of other clusters — this is intentional for E).
EOF
    ;;

  *)
    echo "❌ Unknown cluster: $CLUSTER (must be one of: a, b, c, d, e)" >&2
    rm "$PROMPT_FILE"
    exit 3
    ;;
esac

# --- Generate ---
echo "[make-poster] prompt written to $PROMPT_FILE ($(wc -l < "$PROMPT_FILE") lines)"

# Save the prompt next to the output for reproducibility (always, even on --dry-run)
PROMPT_SAVED="${OUTPUT%.*}.prompt.txt"
cp "$PROMPT_FILE" "$PROMPT_SAVED"

if [ "$DRY_RUN" -eq 1 ]; then
  rm "$PROMPT_FILE"
  echo ""
  echo "[make-poster] DRY RUN - skipped OpenRouter call."
  echo "   Prompt: $PROMPT_SAVED"
  echo "   (rerun without --dry-run to render $OUTPUT)"
  exit 0
fi

echo "[make-poster] calling generate.sh..."

bash "$SCRIPT_DIR/generate.sh" "$PROMPT_FILE" "$OUTPUT" || {
  echo "ERROR: generate.sh failed" >&2
  rm -f "$PROMPT_FILE"
  exit 4
}

rm "$PROMPT_FILE"

echo ""
echo "[make-poster] Poster generated:"
echo "   Image:  $OUTPUT"
echo "   Prompt: $PROMPT_SAVED"
