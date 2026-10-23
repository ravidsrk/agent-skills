# DESIGN.md compliance

The system axis compares the live DOM against the page's own declared design system. A page can score clean on slop and still be off-system. This axis answers: "does the page do what it said it would do?"

# Declare the system

`DESIGN.md` is a human-readable spec. A DTCG `tokens.json` is the machine-readable equivalent. Either is enough; both is better.

```md
# Design System

## Color
- background: #0e0e0f
- surface: #17171a
- text: #f5f5f4
- muted: #a1a1aa
- accent: #ff5c35

## Type
- display: "Instrument Serif", 64/1.05, -0.03em
- body: "Inter", 17/1.6, 0
- mono: "JetBrains Mono", 14/1.5, 0

## Space
- base: 4px
- section: 96px desktop / 64px mobile

## Radius
- control: 8px
- card: 16px

## Elevation
- card: 0 1px 2px rgb(0 0 0 / 0.2)
```

```json
{
  "color": {
    "background": { "$value": "#0e0e0f", "$type": "color" },
    "accent": { "$value": "#ff5c35", "$type": "color" }
  },
  "typography": {
    "display": { "$value": { "fontFamily": "Instrument Serif", "fontSize": "64px" }, "$type": "typography" }
  }
}
```

# Nine checks

| Check | What it compares | Failure looks like |
|---|---|---|
| 1. Palette | Declared colors vs computed colors | A near-black page uses pure `#000` and a random blue |
| 2. Accent | Declared accent vs interactive/highlight color | Two different oranges; accent used as a background wash |
| 3. Type roles | Display/body/mono assignments | Body font used for the H1; mono used for prose |
| 4. Type scale | Declared sizes/line heights vs computed | 13 ad-hoc sizes; line height below 1.3 for body |
| 5. Spacing | Declared base/section rhythm vs margins/padding | 13/17/23px gaps; sections drift by 4px |
| 6. Radius | Declared control/card radii vs computed | Mixed 4/8/12/999px on the same surface class |
| 7. Elevation | Declared shadow vs computed | Bordered cards plus heavy shadows; inconsistent depth |
| 8. Component states | Declared hover/focus/disabled vs implemented | No visible focus ring; hover moves layout |
| 9. Motion | Declared duration/easing vs implemented | Every section fades up; 600ms hovers |

# Score bands

- Aligned: ≥80
- Drifting: 50–79
- Off-system: <50

# Workflow

1. Locate `DESIGN.md` or `tokens.json`. Prefer the repo file over the rendered page.
2. Scan with `designMd: true` (or `--design-md auto`).
3. For each failed check, quote the declared value and the computed value.
4. Fix the token or the component, not the report.
5. Re-scan.

# Creating a DESIGN.md from scratch

```bash
npx -y slop-detect https://example.com --init-design-md > DESIGN.md
npx -y slop-detect https://example.com --init-tokens > tokens.json
```

Edit the generated file before committing. A generated spec that describes the current page will always pass; it is useful as a starting point, not as an excuse.

# Linting and diffing

```bash
npx -y slop-detect --lint-design-md ./DESIGN.md
npx -y slop-detect --diff-design-md ./base/DESIGN.md ./head/DESIGN.md
```

Use the diff in a PR when a design-system change is intentional. An unexplained token change is drift even if it looks fine.

# Rules

- The declared system is the source of truth, not the current DOM.
- A page can be intentionally off-system for a campaign; mark the exception and scope it.
- Do not add a token just to make the audit pass.
- Do not copy another company's design system into `DESIGN.md`.
- Report drift separately from the design-slop score. They measure different things.
