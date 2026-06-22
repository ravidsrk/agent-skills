"""Exa neural web search — routed through monid (blockrun.ai Exa proxy).

Migrated 2026-06-22 from the direct Exa API (EXA_API_KEY) to the monid catalog
endpoint `blockrun.ai /api/v1/exa/search`. Reason: the direct key hit a hard
credit wall mid-run (HTTP 402 NO_MORE_CREDITS) and silently returned 0 items.
Routing through monid shares the workspace balance with every other source and
removes a per-vendor credit dependency. Same Exa engine, same ~$0.011/call.

The proxy supports a `category` filter (research paper, news, github, tweet,
company, pdf, personal site, linkedin profile, financial report) and a
`contents` option that returns `text` + `highlights` inline.

Required env: MONID_API_KEY (workspace-wide).
"""
from __future__ import annotations
import json
import sys
from typing import Optional

from ._monid import run_monid, extract_output


def _normalize(r: dict) -> dict:
    url = r.get("url", "") or ""
    domain = ""
    if url:
        parts = url.split("/")
        domain = parts[2] if len(parts) > 2 else ""
    hl = r.get("highlights") or []
    if isinstance(hl, str):
        hl = [hl]
    return {
        "title": r.get("title", "") or "",
        "url": url,
        "author": r.get("author", "") or "",
        "published_date": r.get("publishedDate", "") or r.get("published_date", "") or "",
        "domain": domain,
        "text": (r.get("text") or "")[:3000],
        "highlights": hl,
        "score": r.get("score", 0) or 0,
    }


def search(
    topic: str,
    from_date: str = "",
    to_date: str = "",
    limit: int = 12,
    include_text: bool = True,
    category: Optional[str] = None,
) -> list[dict]:
    """Neural web search via the monid Exa proxy.

    Args:
        topic: query string
        from_date, to_date: kept for signature compatibility with the old direct
            Exa source. The proxy body does not expose date filters, so these are
            accepted but unused (the orchestrator still records the window).
        limit: max results (proxy max 100)
        include_text: request inline text + highlights for quoting
        category: optional Exa category filter
    """
    body: dict = {"query": topic, "numResults": limit}
    if category:
        body["category"] = category
    if include_text:
        body["contents"] = {"text": True, "highlights": True}

    sys.stderr.write(
        f"[exa] monid proxy search {topic!r} (limit={limit}"
        f"{', cat=' + category if category else ''})\n"
    )
    result = run_monid("blockrun.ai", "/api/v1/exa/search", body=body, wait=60, tag="exa")
    output = extract_output(result)
    if not output:
        return []
    # Proxy returns {"results": [...]} under output
    results = output.get("results") if isinstance(output, dict) else output
    if not isinstance(results, list):
        return []
    out = [_normalize(r) for r in results if isinstance(r, dict)]
    sys.stderr.write(f"[exa] got {len(out)} results via monid\n")
    return out


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "AI coding agent memory scope creep"
    results = search(topic, limit=6)
    print(json.dumps(results, indent=2, default=str))
