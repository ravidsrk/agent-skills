# AEO readiness

16 checks for whether a page can be fetched, indexed, and cited by answer engines. Higher score = better. Tiers: Eligible ≥80, Partially eligible 50–79, Restricted <50.

| Check | Points | Requirement | How to verify | If it fails |
|---|---|---|---|---|
| `html.reachable` | 10 | Server returns HTML with a 2xx/3xx | `curl -sI` | Fix hosting, redirects, or bot blocking |
| `edge.access` | 20 | CDN/WAF does not block the scanner | `curl -A "slop-detect"` | Allow the user agent or remove the challenge |
| `robots.searchAllowed` | 20 | `robots.txt` allows the page | Fetch `/robots.txt` | Remove the disallow for public pages |
| `html.indexable` | 12 | No `noindex` on the canonical URL | Inspect `<meta name="robots">` | Remove `noindex` from public pages |
| `ai.previewControls` | 8 | Preview controls are intentional | Inspect `X-Robots-Tag` / meta | Do not block AI previews by accident |
| `html.serverTextCoverage` | 15 | Main content exists in server HTML | `curl -s URL \| grep '<h1'` | Server-render or prerender the content |
| `md.twin` | 6 | A Markdown twin exists | Check `/page.md` or `rel=alternate` | Publish a Markdown version |
| `html.linkAlternate` | 3 | `rel=alternate` points to the twin | Inspect `<head>` | Add `type="text/markdown"` alternate |
| `site.llmsTxt` | 2 | `llms.txt` describes the site | Fetch `/llms.txt` | Add a short `llms.txt` |
| `html.vary` | 4 | `Vary` is set correctly for content negotiation | Inspect response headers | Add `Vary: Accept` when serving twins |
| `ai.manipulation` | 0 | No hidden prompt-injection text | Search invisible text | Remove it |
| `agent.operability` | 0 | Agents can perform the primary action | Inspect forms/links | Add a machine-readable path |
| `agent.discovery` | 0 | Agents can discover the API/CLI | Check docs links | Link the docs |
| `ai.usagePolicy` | 0 | AI usage policy is stated | Check `/ai.txt` or terms | State the policy |
| `content.dates` | 0 | Content dates are visible | Inspect byline/schema | Add published/updated dates |
| `jsonld.hygiene` | 0 | JSON-LD is valid and matches the page | Validate with a schema tool | Fix types, URLs, and required fields |

# Required vs recommended

Required blockers: `html.reachable`, `edge.access`, `robots.searchAllowed`, `html.indexable`, `ai.previewControls`, `html.serverTextCoverage`. A page that fails one of these is not AEO-eligible regardless of the other points.

Recommended: `md.twin`, `html.linkAlternate`, `site.llmsTxt`, `html.vary`.

Informational: the remaining checks. Report them, but do not let them dominate the verdict.

# Remediation order

1. Make the page reachable (2xx, no bot challenge).
2. Allow search indexing.
3. Server-render the main content.
4. Remove accidental AI-preview blocks.
5. Fix structured data.
6. Add a Markdown twin and `rel=alternate`.
7. Add `llms.txt` and content dates.
8. Re-scan.

# Verification commands

```bash
curl -sI https://example.com
curl -s https://example.com/robots.txt
curl -s https://example.com | grep -iE '<title|<h1|noindex|rel="alternate"'
curl -s https://example.com/llms.txt
```

Do not claim an AEO fix without a fresh scan showing the check passing.

# Notes

- The scanner uses its own user agent and does not impersonate Googlebot, GPTBot, or any vendor crawler.
- A CDN rule that blocks unknown user agents is a common cause of a low AEO score even when the page is public.
- A Markdown twin should contain the same substance as the page, not a stub.
- `noindex` on a staging domain is correct; do not "fix" it by indexing staging.
