# landing-page-craft

Audit a landing page for AI-slop design patterns, synthetic copy, design-system drift, and answer-engine readiness — then fix it in impact order.

## What it does

- Scores 45 design patterns and 26 copy patterns.
- Checks whether the live DOM honors the project's `DESIGN.md` or DTCG tokens.
- Checks 16 answer-engine readiness conditions.
- Reports a separate craft floor so craft is not hidden inside a slop score.
- Produces a copy-pasteable fix prompt and a prioritized fix plan.
- Re-scans after fixes so the same pattern cannot silently remain.

The engine is [slop-detect](https://github.com/ravidsrk/slop-detect) (MIT). The pattern catalogue is versioned; weight-0 rules are listed but do not add points.

## When to use

- "Audit my landing page" / "review my landing page"
- "Does this look AI-generated?" / "why does this look generic?"
- "Slop score" / "template tells"
- "Does my site honor its DESIGN.md?"
- "Can ChatGPT / Claude / Perplexity read and cite my site?"
- Before a launch or a redesign

## Install

Hosted scan needs `curl` and `jq`. Local scans need Node.js:

```bash
node --version   # 20+
curl --version
jq --version
```

Optional local CLI:

```bash
npx -y slop-detect https://example.com
```

Optional MCP host: start `npx -y slop-detect-mcp` and use `scan_page`, `check_aeo`, `check_design_system`, `fix_prompt`.

## Usage

```bash
# Design + copy + DESIGN.md compliance
bash scripts/scan.sh https://example.com --design

# Add AEO
bash scripts/scan.sh https://example.com --design --aeo

# Generate a fix prompt
bash scripts/scan.sh https://example.com --fix > fix.md

# Localhost / private page
bash scripts/scan.sh http://localhost:3000 --local --design
```

Raw API:

```bash
curl -s -X POST https://slop-detect.com/api/scan \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com","axes":["design","copy"],"designMd":true}' | jq .
```

## Output

- One-line verdict with tier and letter grade
- Triggered patterns with weight and literal evidence
- Design, copy, system, AEO, and craft-floor readouts
- The single highest-impact fix
- A prioritized fix order
- An optional copy-pasteable remediation prompt

## Cost and latency

- Hosted API: free, rate-limited per IP; roughly 5–8 seconds per scan.
- Local CLI/MCP: compute only; needs Playwright for localhost rendering.

## File layout

```
landing-page-craft/
├── SKILL.md
├── README.md
├── references/
│   ├── design-patterns.md
│   ├── copy-patterns.md
│   ├── aeo.md
│   ├── design-md.md
│   └── fix-playbook.md
└── scripts/
    └── scan.sh
```

## Known gotchas

| Gotcha | Fix |
|---|---|
| Hosted scan cannot reach localhost | Use `--local` or the MCP server's local mode |
| Auth-gated page returns a login screen | Scan a preview URL with a test account, or scan locally |
| Low score but still generic | Check weight-0 review rules and the craft floor; re-read the hero |
| Replacing one pattern with another | Consult the fix playbook before changing fonts/colors |
| AEO varies between runs | The scanner uses its own user agent and network path; verify reachability |
| Copy is clean but design is heavy | Fix the design axis; do not rewrite clean copy |

## Pairs with

- A design-system review (`DESIGN.md` + tokens) when the page must match a product surface.
- An OG-image generator when the page has no custom social card.

## Credits

- Rubric, pattern definitions, AEO checks, and fix recipes adapted from [slop-detect](https://github.com/ravidsrk/slop-detect) (MIT, Copyright (c) 2026 Ravindra Kumar).

## License

MIT
