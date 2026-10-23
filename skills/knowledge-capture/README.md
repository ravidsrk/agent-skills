# knowledge-capture

One command to save a thought, article, meeting, or voice note into a markdown knowledge base — with stable frontmatter, a content-hash slug, dedupe, and backlinks.

## What it does

- Captures inline text, a file, or stdin.
- Routes to `inbox/` by default; supports explicit folders for meetings, people, companies, ideas, originals, and voice notes.
- Writes frontmatter (`title`, `type`, `slug`, `captured_at`, `content_hash`, `source`, `tags`).
- Dedupes the same content by SHA-256.
- Preserves the original body; synthesis goes in a separate section.
- Enforces a backlink from durable entity pages.

Plain markdown + bash. Optional [gbrain](https://github.com/garrytan/gbrain) backend for semantic enrichment and a richer ingest pipeline.

## When to use

- "Capture this" / "save this thought" / "remember this"
- "Drop this in my inbox" / "save to my brain"
- "Ingest this article" / "save this link"
- "Process this meeting transcript"
- "Save this voice note"
- After a research session or meeting

## Install

```bash
export KB_ROOT="${KB_ROOT:-$HOME/brain}"
mkdir -p "$KB_ROOT/inbox"
chmod +x scripts/capture.sh
```

No package install required. `shasum` or `sha256sum` must be available.

Optional gbrain:

```bash
# Install per https://github.com/garrytan/gbrain
gbrain init
```

## Usage

```bash
# Inline
bash scripts/capture.sh "The pricing experiment should test annual-only first."

# File
bash scripts/capture.sh --file ./notes/today.md --type note

# Stdin
cat transcript.txt | bash scripts/capture.sh --stdin --type meeting --title "Pricing review"

# Explicit slug
bash scripts/capture.sh --file article.md --slug originals/2026-05-21-postgres-vs-sqlite

# Machine-readable receipt
bash scripts/capture.sh "a thought" --json

# Slug only (for shell pipelines)
SLUG=$(bash scripts/capture.sh "a thought" --quiet)
```

## What lands on disk

```
$KB_ROOT/
└── inbox/
    └── 2026-05-21-f3a7b9c0.md
```

```md
---
title: "The pricing experiment"
type: "note"
slug: "inbox/2026-05-21-f3a7b9c0"
captured_at: "2026-05-21T09:30:00Z"
captured_via: "capture.sh"
content_hash: "f3a7b9c0d1e2f3a4..."
---

# The pricing experiment

The pricing experiment should test annual-only first.
```

## File layout

```
knowledge-capture/
├── SKILL.md
├── README.md
├── references/
│   ├── routing.md
│   ├── frontmatter.md
│   ├── backlinks.md
│   └── specialized-ingest.md
└── scripts/
    └── capture.sh
```

## Known gotchas

| Gotcha | Fix |
|---|---|
| Body loses trailing newlines | Use `--file`/`--stdin`; the script writes the file content directly |
| Duplicate captures | The content hash dedupes; the second run returns the first slug |
| YAML parse error on a title | Quote titles with `"` and escape embedded quotes; see `references/frontmatter.md` |
| Slug escapes `$KB_ROOT` | The script rejects `..`, absolute paths, and empty segments |
| Voice note paraphrased | Keep the verbatim transcript; put the summary in a separate section |
| Secret captured | Do not capture secrets; redact before writing |
| Agent belief presented as user fact | Set `provenance: agent` and label the claim |

## Pairs with

- `knowledge-query` — find and cite what was captured.
- `knowledge-maintenance` — audit frontmatter, links, and stale pages.

## Credits

- Capture contract, routing model, frontmatter conventions, and back-link law adapted from [gbrain](https://github.com/garrytan/gbrain) (MIT, Copyright (c) 2026 Garry Tan).

## License

MIT
