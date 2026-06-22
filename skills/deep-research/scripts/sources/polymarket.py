"""Polymarket prediction-market search via Gamma API — routed through monid.

Migrated 2026-06-22 to route the Gamma `public-search` call through monid's
`exa/contents` proxy (via `_monid.fetch_json`) so Polymarket billing flows
through the single MONID_API_KEY balance (per the "everything through monid"
decision). Gamma has a native monid endpoint only for market *detail* (requires
a slug), not keyword search — so we proxy the search URL and parse the raw JSON.

⚠️ Size ceiling: exa livecrawl 504s on ~1MB+ responses, and Gamma's payload is
large (full event descriptions). `limit_per_type=8` (~880KB) is the reliable
max — verified 2026-06-22. fetch_json retries transient 504s automatically.

Endpoint: https://gamma-api.polymarket.com/public-search
Returns market events with odds, volume, and outcome details. Useful for any
research that touches predictions, regulatory deadlines, election or trial
outcomes, project milestones, or "what does the money think" signals.
"""
from __future__ import annotations
import json
import sys
import urllib.parse
from typing import Optional

from ._monid import fetch_json

GAMMA_URL = "https://gamma-api.polymarket.com/public-search"
# exa livecrawl 504s above ~1MB; 8 events/type keeps Gamma payload ~880KB.
_MAX_LIMIT = 8


def _get_json(url: str, timeout: int = 120) -> Optional[dict]:
    data = fetch_json(url, tag="polymarket", wait=timeout)
    return data if isinstance(data, dict) else None


def _norm_event(e: dict) -> dict:
    markets = e.get("markets", []) or []
    market_summaries = []
    for m in markets[:5]:
        outcomes = m.get("outcomes", "") or ""
        prices = m.get("outcomePrices", "") or ""
        # Parse JSON-string fields
        try:
            outcomes_l = json.loads(outcomes) if isinstance(outcomes, str) else outcomes
        except Exception:
            outcomes_l = []
        try:
            prices_l = json.loads(prices) if isinstance(prices, str) else prices
        except Exception:
            prices_l = []
        market_summaries.append({
            "question": m.get("question", ""),
            "outcomes": outcomes_l,
            "outcome_prices": prices_l,
            "volume": m.get("volume", 0),
            "liquidity": m.get("liquidity", 0),
            "end_date": m.get("endDate", ""),
            "url": f"https://polymarket.com/event/{e.get('slug', '')}",
        })
    return {
        "title": e.get("title", ""),
        "slug": e.get("slug", ""),
        "description": (e.get("description", "") or "")[:800],
        "url": f"https://polymarket.com/event/{e.get('slug', '')}",
        "start_date": e.get("startDate", ""),
        "end_date": e.get("endDate", ""),
        "volume": e.get("volume", 0),
        "liquidity": e.get("liquidity", 0),
        "markets": market_summaries,
    }


def search(topic: str, limit: int = 15) -> list[dict]:
    """Find Polymarket events related to the topic (via monid exa/contents)."""
    q = urllib.parse.quote_plus(topic)
    capped = min(limit, _MAX_LIMIT)  # exa livecrawl 504s on Gamma's >~1MB payload
    url = f"{GAMMA_URL}?q={q}&limit_per_type={capped}&events_status=active"
    sys.stderr.write(f"[polymarket] search {topic!r} (limit={capped}, via monid)\n")
    data = _get_json(url)
    if not data:
        return []
    events = data.get("events", []) or []
    out = [_norm_event(e) for e in events]
    # Drop events with no volume at all (dead markets)
    out = [e for e in out if (e.get("volume", 0) or 0) > 100]
    sys.stderr.write(f"[polymarket] got {len(out)} active markets\n")
    return out


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "AI agents"
    events = search(topic, limit=10)
    print(json.dumps(events, indent=2, default=str))
