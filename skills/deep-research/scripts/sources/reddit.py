"""Reddit search via monid Apify (trudax/reddit-scraper-lite).

The public reddit.com JSON endpoints return 403 from datacenter IPs (verified
2026-05-13). The Apify scraper paths through Reddit at $0.0057/result and
returns the same shape as the public JSON, including comments.

Required env: MONID_API_KEY (already set workspace-wide).
"""
from __future__ import annotations
import json
import os
import subprocess
import sys
import time
from typing import Optional


from ._monid import MONID_BIN


def _run_monid(provider: str, endpoint: str, body: dict, wait: int = 90) -> Optional[dict]:
    """Run monid and return the parsed JSON result."""
    cmd = [
        MONID_BIN, "run",
        "-p", provider,
        "-e", endpoint,
        "-i", json.dumps(body),
        "-w", str(wait),
        "--json",
    ]
    env = {**os.environ, "NO_COLOR": "1"}
    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=wait + 30)
        if result.returncode != 0:
            sys.stderr.write(f"[reddit/monid] non-zero exit: {result.stderr[:500]}\n")
            return None
        # Parse — strip ANSI just in case
        out = result.stdout
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            # Sometimes the CLI emits a leading status line; find first '{'
            i = out.find("{")
            if i == -1:
                return None
            return json.loads(out[i:])
    except subprocess.TimeoutExpired:
        sys.stderr.write(f"[reddit/monid] timeout\n")
        return None
    except Exception as e:
        sys.stderr.write(f"[reddit/monid] error: {e}\n")
        return None


def _normalize_post(p: dict) -> dict:
    """Normalize a single Reddit item from the Apify scraper output."""
    # The trudax scraper has slightly different field names than the public JSON
    sub = p.get("communityName") or p.get("subreddit") or ""
    # Apify returns "r/foo" — strip the prefix so we can render "r/foo" once in templates
    if sub.startswith("r/"):
        sub = sub[2:]
    return {
        "title": p.get("title") or "",
        "subreddit": sub,
        "author": p.get("username") or p.get("author") or "",
        "url": p.get("url") or "",
        "external_url": (
            p.get("link") or ""
            if p.get("link") and "reddit.com" not in (p.get("link") or "")
            else ""
        ),
        "score": p.get("upVotes") or p.get("score") or 0,
        "num_comments": p.get("numberOfComments") or p.get("num_comments") or 0,
        "created_at": p.get("createdAt") or "",
        "body": (p.get("body") or p.get("selftext") or "")[:1500],
        "comments": [
            {
                "author": c.get("username") or c.get("author") or "",
                "score": c.get("upVotes") or c.get("score") or 0,
                "body": (c.get("body") or c.get("text") or "")[:600],
            }
            for c in (p.get("comments") or [])[:5]
            if (c.get("upVotes") or c.get("score") or 0) >= 3 and (c.get("body") or c.get("text") or "")
        ],
        "data_type": p.get("dataType") or "post",
    }


def search(topic: str, time_filter: str = "month", limit: int = 25, include_comments: bool = True) -> list[dict]:
    """Global Reddit search for the topic.

    Args:
        topic: search term
        time_filter: kept for API compatibility — Apify scraper uses postDateLimit
        limit: max posts to return
        include_comments: pull top comments per post for direct quote material
    """
    from datetime import datetime, timedelta, timezone
    # postDateLimit format is YYYY-MM-DD
    since = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%d")
    body = {
        "searches": [topic],
        "type": "posts",
        "sort": "relevance",
        "maxItems": limit,
        "maxPostCount": limit,
        "maxComments": 5 if include_comments else 0,
        "skipComments": not include_comments,
        "skipUserPosts": True,
        "skipCommunity": True,
        "postDateLimit": since,
    }
    sys.stderr.write(f"[reddit] search via monid: {topic!r} since={since} limit={limit}\n")
    result = _run_monid("apify", "/trudax/reddit-scraper-lite", body, wait=120)
    if not result:
        return []
    items = result.get("output") or []
    if not isinstance(items, list):
        return []
    # Filter out non-post items
    posts = [_normalize_post(p) for p in items if (p.get("dataType") or "post") == "post"]
    # The Apify scraper sometimes returns upVotes=1 even for high-engagement posts
    # (scraping skips the engagement layer). Keep all posts; let downstream rank.
    # Only drop obvious spam: zero score AND zero comments.
    posts = [p for p in posts if (p["score"] or 0) > 0 or (p["num_comments"] or 0) > 0 or p.get("body") or len(p.get("comments") or []) > 0]
    sys.stderr.write(f"[reddit] got {len(posts)} qualifying posts (from {len(items)} raw items)\n")
    return posts


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "Hermes Agent"
    posts = search(topic, limit=15)
    print(json.dumps(posts, indent=2, default=str))
