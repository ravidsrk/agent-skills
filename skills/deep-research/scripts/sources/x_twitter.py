"""X (Twitter) search — routed through monid (tikhub Twitter web search).

Migrated 2026-06-22 from xAI's Agent Tools API (XAI_API_KEY) to the monid
catalog endpoint `tikhub /api/v1/twitter/web/fetch_search_timeline`. Reasons:
- consolidate auth/billing onto MONID_API_KEY (one balance, no per-vendor key)
- cheaper ($0.0015/call vs ~$0.02 for the xAI tool)
- richer raw data: real verbatim tweets with favorites/retweets/replies/views,
  rather than an LLM re-summarizing search results.

tikhub returns ~20 tweets/page (Top or Latest) and supports cursor paging for
`deep` depth. Date filtering is applied client-side from `created_at` because
the endpoint has no date param. There is no LLM "why_relevant" field anymore —
the orchestrator ranks by engagement instead.

Required env: MONID_API_KEY (workspace-wide).
"""
from __future__ import annotations
import json
import sys
from datetime import datetime, timezone
from typing import Optional

from ._monid import run_monid, extract_output


ENDPOINT = "/api/v1/twitter/web/fetch_search_timeline"

# depth → (pages, per-page target). tikhub returns ~20/page.
DEPTH_PAGES = {"quick": 1, "default": 2, "deep": 3}


def _parse_date(s: str) -> Optional[str]:
    """Parse tikhub's 'Sun Jun 21 20:15:00 +0000 2026' → 'YYYY-MM-DD'."""
    if not s:
        return None
    try:
        dt = datetime.strptime(s, "%a %b %d %H:%M:%S %z %Y")
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")
    except (ValueError, TypeError):
        return None


def _normalize(t: dict) -> dict:
    ui = t.get("user_info") or {}
    handle = t.get("screen_name") or ui.get("screen_name") or ""
    tid = t.get("tweet_id") or ""
    url = f"https://x.com/{handle}/status/{tid}" if handle and tid else ""
    return {
        "text": (t.get("text") or "").strip(),
        "url": url,
        "author": handle,
        "author_name": ui.get("name", "") or "",
        "date": _parse_date(t.get("created_at", "")) or "",
        "likes": t.get("favorites", 0) or 0,
        "reposts": t.get("retweets", 0) or 0,
        "replies": t.get("replies", 0) or 0,
        "quotes": t.get("quotes", 0) or 0,
        "views": t.get("views", 0) or 0,
        "bookmarks": t.get("bookmarks", 0) or 0,
        "why_relevant": "",  # no LLM annotation on the raw tikhub path
    }


def _fetch_page(keyword: str, search_type: str, cursor: str = "") -> tuple[list[dict], str]:
    """One tikhub search page → (raw tweet items, next_cursor)."""
    query = {"keyword": keyword, "search_type": search_type}
    if cursor:
        query["cursor"] = cursor
    result = run_monid("tikhub", ENDPOINT, query=query, wait=60, tag="x")
    output = extract_output(result)
    if not output or not isinstance(output, dict):
        return [], ""
    timeline = output.get("timeline") or []
    tweets = [t for t in timeline if isinstance(t, dict) and t.get("type") == "tweet"]
    next_cursor = output.get("next_cursor", "") or ""
    return tweets, next_cursor


def search(
    topic: str,
    from_date: str = "",
    to_date: str = "",
    depth: str = "default",
) -> list[dict]:
    """Search X for the topic via monid tikhub, ranked by engagement.

    Args:
        topic: search keyword (kept short; tikhub matches full-text)
        from_date, to_date: YYYY-MM-DD window for client-side date filtering
        depth: quick|default|deep → controls how many pages to pull
    """
    pages = DEPTH_PAGES.get(depth, 2)
    sys.stderr.write(f"[x] tikhub search {topic!r} depth={depth} pages={pages}\n")

    raw: list[dict] = []
    seen: set[str] = set()
    cursor = ""
    # Pull a couple pages from "Top" (high-signal). Deep adds a "Latest" sweep.
    for i in range(pages):
        tweets, cursor = _fetch_page(topic, "Top", cursor)
        for t in tweets:
            tid = str(t.get("tweet_id") or "")
            if tid and tid not in seen:
                seen.add(tid)
                raw.append(t)
        if not cursor or not tweets:
            break
    if depth == "deep":
        latest, _ = _fetch_page(topic, "Latest")
        for t in latest:
            tid = str(t.get("tweet_id") or "")
            if tid and tid not in seen:
                seen.add(tid)
                raw.append(t)

    out = [_normalize(t) for t in raw]
    # Client-side date window filter (skip items we couldn't date)
    if from_date or to_date:
        def _in_window(d: str) -> bool:
            if not d:
                return True  # keep undated rather than silently drop
            if from_date and d < from_date:
                return False
            if to_date and d > to_date:
                return False
            return True
        out = [p for p in out if _in_window(p["date"])]
    # Drop empty-text/retweet-only noise
    out = [p for p in out if p["text"]]
    sys.stderr.write(f"[x] got {len(out)} tweets via monid (from {len(raw)} raw)\n")
    return out


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "AI agent memory"
    posts = search(topic, depth="default")
    print(json.dumps(posts, indent=2, default=str))
