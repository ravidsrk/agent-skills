---
name: landing-page-craft
description: >-
  Audit any landing page for default-template design patterns, AI-slop copy,
  DESIGN.md drift, and answer-engine readiness, then produce a deterministic fix
  plan. Use when the user asks "does this look AI-generated?", "audit my landing
  page", "slop score", "why does this site look generic?", "can ChatGPT cite my
  site?", or wants a marketing page reviewed before launch.
license: MIT
compatibility: Requires curl and jq for the hosted scan. Optional slop-detect CLI (npx) or MCP server for localhost/private pages and offline scoring.
metadata:
  version: "0.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Landing Page Craft

Score a landing page the way a skeptical design reviewer would: what makes it look like every other AI-generated page, what makes the copy sound synthetic, whether it honors its own design system, and whether answer engines can read it. Then fix the highest-impact issues first.

The scoring engine is [slop-detect](https://github.com/ravidsrk/slop-detect). Its pattern catalogue is versioned; this skill carries the workflow, the output contract, and the fix playbook.

# When to use

- "Audit my landing page" / "review my landing page"
- "Does this look AI-generated?" / "why does this look generic?"
- "Slop score" / "design slop" / "template tells"
- "Does my site honor its DESIGN.md?"
- "Can ChatGPT / Claude / Perplexity read and cite my site?"
- Before launching or redesigning a marketing page
- After a hero rewrite that still feels flat

# When NOT to use

- App UI behind auth. The scanner needs a reachable page.
- Pure copy editing with no design or AEO question — use a copy review.
- A page that is intentionally a template or a wireframe.
- You need a full UX research study; this is a pattern audit, not user research.

# Inputs

| Input | Required | Notes |
|---|---|---|
| Page URL | yes | Public URL, or `localhost` with the local CLI |
| `DESIGN.md` or DTCG `tokens.json` | optional | Enables the system-compliance axis |
| Target tier | optional | `Clean` for a strict bar, `Mild` for a first pass |
| Audience / category | optional | Used to judge whether the H1 is concrete |

# What gets scored

Four independent axes plus a craft floor:

| Axis | What it measures | Better direction |
|---|---|---|
| Design slop | 45 CSS/DOM patterns associated with default-template output | lower |
| Copy slop | 26 prose patterns associated with synthetic marketing copy | lower |
| System compliance | Whether the live DOM honors the page's declared `DESIGN.md` / tokens (9 checks) | higher |
| AEO readiness | Whether crawlers and answer engines can fetch, index, and cite the page (16 checks) | higher |
| Craft floor | 11 baseline craft checks, reported separately | higher |

The design and copy scores never blend. A page can be visually clean and copy-sloppy, or vice versa.

# Scoring tiers

| Axis | Clean | Mild | Heavy |
|---|---|---|---|
| Design | 0–9 | 10–27 | ≥28 |
| Copy | 0–7 | 8–19 | ≥20 |
| System | Aligned ≥80 | Drifting 50–79 | Off-system <50 |
| AEO | Eligible ≥80 | Partially eligible 50–79 | Restricted <50 |

Weight-0 rules are listed in the catalogue but do not add points until they are promoted. Do not invent scores for them.

# The workflow

## Step 1 — Scan

Hosted API (fastest, no install):

```bash
bash scripts/scan.sh https://example.com --design --aeo
```

Equivalent raw call:

```bash
curl -s -X POST https://slop-detect.com/api/scan \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","axes":["design","copy"],"designMd":true}' | jq .
```

Localhost or a private page:

```bash
npx -y slop-detect http://localhost:3000 --copy --craft --design-md auto
```

MCP host:

```text
scan_page → check_aeo → check_design_system → fix_prompt
```

If no scanner is available, use the manual rubric in `references/design-patterns.md` and `references/copy-patterns.md`. Read the page source and the rendered hero, not just a screenshot.

## Step 2 — Read the evidence, not just the score

For every triggered pattern, collect:

- the pattern ID and weight
- the literal DOM/CSS or copy evidence (selector, line, text)
- whether the rule is active, decaying, review, or retired

A score without evidence is not actionable. If the scanner returns only a number, inspect the page yourself and map the strongest tells to the catalogue.

## Step 3 — Report

Use this shape:

```markdown
# Landing Page Audit: {project}

**URL:** {url}
**Audited:** {YYYY-MM-DD}
**Design slop:** {n}/… {tier}
**Copy slop:** {n}/… {tier}
**System:** {Aligned|Drifting|Off-system} ({score}/100)
**AEO:** {Eligible|Partially eligible|Restricted} ({score}/100)
**Craft floor:** {score}/100

## 🔴 Triggered patterns
- `pattern_id` (weight N) — {evidence}. Fix: {one concrete change}.

## 🟢 What works
- {specific, cited observation}

## 🎯 Single highest-impact fix
{One change with the exact replacement copy or CSS.}

## Fix order
1. ...
2. ...
3. ...
```

## Step 4 — Fix in impact order

For most pages:

1. **Rewrite the H1** as `[Category] for [audience]`. This alone fixes several copy patterns and clarifies the page.
2. **Remove the fake-news eyebrow** (sparkle pill, "AI-powered", "now in beta" with no real news).
3. **Replace "Sign up" / "Get started"** with a verb + outcome CTA.
4. **Remove the gradient/glow/glass stack** and pick one accent on a flat surface.
5. **Replace the three-icon card trio** with one product-narrative section (code switcher, transcript, terminal, workflow loop, real screenshot).
6. **Reduce motion** to one purposeful animation or none.
7. **Add a custom OG image** and verify the meta tags.
8. **Fix AEO blockers** (server-rendered text, robots, llms.txt, markdown twin).
9. **Re-scan** and compare axis by axis.

See `references/fix-playbook.md` for copy formulas and examples.

## Step 5 — Re-scan

A fix is not done until the same pattern no longer triggers. Keep the before/after report in the PR or issue.

# AEO checklist (summary)

The full 16-check list is in `references/aeo.md`. The required blockers are:

- the HTML is reachable without JavaScript-only rendering
- edge/CDN access is not blocked for the scanner
- robots rules allow search indexing
- the page is indexable (no `noindex` on the canonical URL)
- AI preview controls are not blocking the page unintentionally
- server text coverage is high enough to read the main content
- a markdown twin, `llms.txt`, and `rel=alternate` are recommended, not required
- structured data is valid, not decorative

# DESIGN.md compliance

If the project declares a design system, the scanner compares the live DOM against it:

- tokens and colors
- type scale and line height
- spacing and radius
- shadow/elevation
- component states
- motion

A page can look fine and still be off-system. Report drift as a separate axis; do not fold it into the slop score.

# Common gotchas

| Gotcha | Fix |
|---|---|
| Localhost scan fails | Use the CLI/MCP local mode; the hosted API cannot reach your machine |
| Auth-gated page returns a login screen | Use a preview URL with a test account or a local scan |
| Score is low but the page still feels generic | Check the weight-0 review rules and the craft floor; re-read the hero and section order |
| Copy is clean but the design is heavy | Fix the design axis; don't keep rewriting copy |
| Replacing one slop pattern with another | Read the fix playbook; Inter → Geist, indigo → violet, gradient text → radial gradient are lateral moves |
| AEO score changes without a deploy | The scanner uses its own user agent and network path; verify reachability from the same region |

# References

- `references/design-patterns.md` — the 45 design patterns, weights, status
- `references/copy-patterns.md` — the 26 copy patterns, weights
- `references/aeo.md` — the 16 AEO checks and remediation
- `references/design-md.md` — DESIGN.md / DTCG system compliance
- `references/fix-playbook.md` — H1, CTA, OG, narrative, typography, motion
- `scripts/scan.sh` — hosted API + CLI fallback wrapper
