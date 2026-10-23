---
name: knowledge-capture
description: >-
  Save a thought, article, meeting, transcript, or voice note into a markdown
  knowledge base with one command — route it to the right folder, generate stable
  frontmatter and a content-hash slug, dedupe re-captures, and preserve exact
  phrasing. Use when the user says "capture this", "save to my brain", "remember
  this", "ingest this article/meeting/voice note", or "drop this in my inbox".
license: MIT
compatibility: Requires bash and shasum or sha256sum. Optional jq for --json receipts; optional gbrain CLI for semantic ingestion and enrichment.
metadata:
  version: "0.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Knowledge Capture

One front door for getting content into a knowledge base. The caller should not have to choose between "put a page", "commit then sync", or "wait for an agent": they capture, and the capture lands as a markdown file with stable metadata, a predictable slug, and a dedupe key.

This skill works against a plain markdown tree (`$KB_ROOT`). If the gbrain CLI is installed, it can route through `gbrain capture` / `gbrain ingest` for semantic enrichment; the file contract stays the same.

# When to use

- "Capture this" / "save this thought" / "remember this"
- "Drop this in my inbox" / "save to my brain"
- "Ingest this article" / "save this link"
- "Process this meeting transcript"
- "Save this voice note" / "transcribe and file this"
- After a research session or meeting, when the synthesis should become a page

# When NOT to use

- Bulk-importing thousands of files — use a sync/import command, not a loop over capture.
- Editing an existing page in place — open the page and edit it.
- Storing secrets, credentials, or production personal data — capture is not an encrypted store.
- A one-off answer that does not need to persist.

# Setup

```bash
export KB_ROOT="${KB_ROOT:-$HOME/brain}"
mkdir -p "$KB_ROOT/inbox"
```

Optional gbrain backend:

```bash
gbrain init
gbrain capture "a thought" --json
```

The generic script has no dependencies beyond bash and a SHA-256 tool:

```bash
bash scripts/capture.sh "the thought I want to remember"
```

# The capture contract

- **Input:** inline text, `--file PATH`, or `--stdin`.
- **Output:** a markdown file under `$KB_ROOT`, plus a receipt with the slug and path.
- **Idempotency:** the same content produces the same content hash and is deduped.
- **Trust:** a local CLI capture is local trust. Do not treat webhook/remote input as trusted without a separate review.
- **Never overwrite:** a different capture that collides on a slug gets a numeric suffix.

# Workflow

## Step 1 — Classify the input

| Input | Route | Why |
|---|---|---|
| A short thought | `inbox/` | Triage later; do not over-file |
| A link/article | `inbox/` first, then `originals/` after enrichment | Preserve the source before summarizing |
| A meeting transcript | `meetings/YYYY-MM-DD-<slug>/` | Attendees, decisions, action items |
| A voice note | `voice-notes/` | Preserve exact phrasing; never paraphrase the original |
| A person/company fact | `people/<slug>/` or `companies/<slug>/` | Entity pages with backlinks |
| A durable idea | `ideas/` or `concepts/` | Reusable across projects |
| A personal reflection | `personal/` | Private by default |
| A file archive | `originals/` or `archive/` | Keep the raw artifact, summarize separately |

When unsure, capture to `inbox/`. Filing is cheap; losing the thought is not.

## Step 2 — Capture

```bash
# Inline
bash scripts/capture.sh "The pricing experiment should test annual-only first."

# File
bash scripts/capture.sh --file ./notes/today.md --type note

# Stdin
cat transcript.txt | bash scripts/capture.sh --stdin --type meeting --title "Pricing review"

# Explicit slug
bash scripts/capture.sh --file article.md --slug originals/2026-05-21-postgres-vs-sqlite
```

The script:

1. Reads the content without stripping trailing newlines.
2. Computes a SHA-256 content hash.
3. Checks existing pages for the same hash and dedupes if found.
4. Derives a title from `--title` or the first non-empty line.
5. Writes frontmatter plus the original body.
6. Prints a receipt.

## Step 3 — Enrich

After capture, add what the raw input does not carry:

- a one-sentence summary at the top
- entities (people, companies, concepts) as links
- the source URL, author, and publication date for articles
- attendees, decisions, and action items for meetings
- a `type` that matches the taxonomy

Do not rewrite the original body. Put synthesis in a clearly marked section above or beside it.

## Step 4 — Link

Every entity mentioned in a durable page should have a backlink from the entity page. See `references/backlinks.md`.

Minimum:

```md
- **2026-05-21** | Referenced in [Pricing review](meetings/2026-05-21-pricing-review.md) — annual-only experiment
```

## Step 5 — Verify

- The file exists at the reported path.
- The frontmatter parses.
- The body matches the input.
- Re-running the same capture does not create a second file.
- Any linked entity page points back.

# Frontmatter

```yaml
---
title: "Pricing review"
type: "meeting"
slug: "meetings/2026-05-21-pricing-review"
captured_at: "2026-05-21T09:30:00Z"
captured_via: "capture.sh"
source: "https://example.com/pricing"
content_hash: "f3a7b9c0d1e2f3a4..."
tags: ['pricing', 'experiment']
---
```

Required: `title`, `type`, `slug`, `captured_at`, `content_hash`.

Recommended: `source`, `tags`, `captured_via`, `provenance`.

`provenance` is one of `user`, `agent`, `external`. An agent-derived belief must not be presented as user truth.

See `references/frontmatter.md` for YAML quoting traps and field definitions.

# Slug rules

- Lowercase letters, digits, and hyphens only.
- No leading/trailing hyphen, no consecutive hyphens.
- Default: `inbox/YYYY-MM-DD-<hash8>`.
- Explicit: `<folder>/<YYYY-MM-DD>-<descriptive-slug>`.
- Never include a file extension.
- Never include `..`, an absolute path, or a user-supplied path segment that escapes `$KB_ROOT`.

# Dedupe

The content hash is the identity. The same text captured twice should return the first page, not a duplicate. If the user wants a new version, edit the page (and update `updated_at`) or capture with a deliberate new slug.

Hash collisions across different content are extremely unlikely; if a slug exists with a different hash, append `-2`, `-3`, and so on.

# Specialized ingestion

- **Articles:** keep the raw text, add source/author/date, then summarize; do not replace the original.
- **Meetings:** capture transcript, then extract attendees, decisions, action items, and open questions.
- **Voice notes:** preserve exact phrasing; transcription cleanup must not change meaning.
- **Media:** store the file or a stable pointer, plus a text description and metadata.
- **Archives:** filter for the user's own writing and high-value relationships; do not ingest everything.

See `references/specialized-ingest.md`.

# Common gotchas

| Gotcha | Fix |
|---|---|
| Trailing newlines removed from the body | Read from a file/stdin; do not echo through command substitution |
| Same capture creates duplicates | Compare `content_hash` before writing |
| YAML breaks on a title with quotes/colons | Use the quoting rules in `references/frontmatter.md` |
| Slug escapes the knowledge base | Reject `..`, absolute paths, and empty segments |
| Voice note paraphrased | Keep the verbatim transcript; summarize separately |
| Article summary replaces the source | Preserve the original body; add a summary section |
| Agent belief written as user fact | Set `provenance: agent` and label it |
| Capture includes a secret | Do not capture secrets; redact before writing |

# References

- `references/routing.md` — input type → destination tree
- `references/frontmatter.md` — fields, YAML quoting, provenance
- `references/backlinks.md` — back-link law, link types, filing rules
- `references/specialized-ingest.md` — media, meetings, voice notes, articles, archives
- `scripts/capture.sh` — generic one-command capture
