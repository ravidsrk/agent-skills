"""Hacker News search via Algolia — routed through monid (exa/contents proxy).

Migrated 2026-06-22 to route the Algolia REST call through monid's
`blockrun.ai/api/v1/exa/contents` proxy so HN billing/auth flows through the
single MONID_API_KEY balance (per the "everything through monid" decision).
Algolia has no native monid endpoint; `exa/contents` returns the upstream HTTP
body verbatim (raw bytes, no markdown cleaning) and `_monid.fetch_json`
json.loads() that directly. NEVER use `surf/web/fetch` here — its markdown
cleaner mangles URLs embedded in JSON strings and corrupts the parse on
prose-heavy fields like `_highlightResult.story_text`.

Defense in depth: this module still passes `attributesToHighlight=["none"]`
and a tight `attributesToRetrieve` whitelist to keep payloads small (no
story_text / comment_text) — useful for cost and response size, not required
for parse correctness now that the raw-passthrough proxy is in place.

Endpoint: https://hn.algolia.com/api/v1/search[_by_date]
"""
from __future__ import annotations
import json
import re
import sys
import time as _time
import urllib.parse
from typing import Optional

from ._monid import fetch_json


# Tight field whitelist — no story_text/comment_text (URL-bearing → cleaner-safe).
_ATTRS = "title,points,num_comments,url,author,created_at,objectID"
# ["none"], url-encoded, disables _highlightResult so no embedded URLs leak in.
_NO_HIGHLIGHT = urllib.parse.quote('["none"]', safe="")


def search(topic: str, days: int = 30, limit: int = 30, mode: str = "popular") -> list[dict]:
    """Search HN by relevance (default) or by date, via monid web/fetch.

    Args:
        topic: query string
        days: window length in days
        limit: max results
        mode: 'popular' (relevance-weighted) or 'recent' (newest first)
    """
    now = int(_time.time())
    since = now - (days * 86400)
    q = urllib.parse.quote_plus(topic)
    base = "search_by_date" if mode == "recent" else "search"
    url = (
        f"https://hn.algolia.com/api/v1/{base}"
        f"?query={q}"
        f"&tags=story"
        f"&numericFilters=created_at_i>{since}"
        f"&hitsPerPage={limit}"
        f"&attributesToRetrieve={_ATTRS}"
        f"&attributesToHighlight={_NO_HIGHLIGHT}"
    )
    sys.stderr.write(f"[hn] search {topic!r} days={days} mode={mode} (via monid)\n")
    data = fetch_json(url, tag="hn")
    if not isinstance(data, dict):
        return []
    hits = data.get("hits", []) or []
    out = []
    for h in hits:
        points = h.get("points", 0) or 0
        n_comments = h.get("num_comments", 0) or 0
        if points < 5 and n_comments < 3:
            continue
        oid = h.get("objectID", "")
        out.append({
            "title": h.get("title", "") or "",
            "url": h.get("url", "") or f"https://news.ycombinator.com/item?id={oid}",
            "hn_url": f"https://news.ycombinator.com/item?id={oid}",
            "author": h.get("author", "") or "",
            "points": points,
            "num_comments": n_comments,
            "created_at": h.get("created_at", "") or "",
            "story_text": "",  # omitted: cleaner-unsafe + not retrieved
            "object_id": oid,
        })
    sys.stderr.write(f"[hn] got {len(out)} qualifying stories\n")
    return out


def get_top_comments(object_id: str, limit: int = 5) -> list[dict]:
    """Fetch top-level comments on an HN story by score, via monid exa/contents.

    Comment text is HTML with embedded links; the exa/contents raw passthrough
    preserves them intact. Not used by the orchestrator's default flow — kept
    for ad-hoc deep dives.
    """
    url = f"https://hn.algolia.com/api/v1/items/{object_id}"
    data = fetch_json(url, tag="hn")
    if not isinstance(data, dict):
        return []
    children = data.get("children", []) or []
    out = []
    for c in children[: limit * 3]:
        text = c.get("text") or ""
        if not text or len(text) < 50:
            continue
        text = re.sub(r"<[^>]+>", " ", text)
        text = re.sub(r"\s+", " ", text).strip()
        out.append({
            "author": c.get("author", "") or "",
            "text": text[:600],
            "created_at": c.get("created_at", "") or "",
            "id": c.get("id"),
        })
        if len(out) >= limit:
            break
    return out


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "AI coding agent"
    stories = search(topic, days=30, limit=20)
    print(json.dumps(stories, indent=2, default=str))
