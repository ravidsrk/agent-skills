"""YouTube research via monid Apify scrapers.

Two phases:
1. Search YouTube for the topic (apify//streamers/youtube-scraper, $0.0045/result)
2. Pull full transcripts for the top N results (apify//starvibe/youtube-video-transcript, $0.0075/result)

Routes through the shared `_monid.run_monid` runner so transient Apify errors
(rate-limit HTML pages, upstream timeouts) get the same exponential-backoff
retry treatment as every other source.

The transcript endpoint often returns 8K+ word transcripts — game-changer
for any research where a podcast or interview is the primary source.
"""
from __future__ import annotations
import json
import re
import sys


from ._monid import run_monid


_VIEW_MAGNITUDES = {"K": 1_000, "M": 1_000_000, "B": 1_000_000_000}
_VIEW_RE = re.compile(r"([0-9]+(?:\.[0-9]+)?)\s*([KMBkmb])?")


def _parse_view_count(raw) -> int:
    """Turn a viewCount / viewCountText into an int.

    Handles bare ints/floats, plain numeric strings ("12345"), comma-separated
    strings ("12,345"), suffixed strings ("1.2M views", "4.5K"), and empty/None.
    """
    if raw is None:
        return 0
    if isinstance(raw, (int, float)):
        try:
            return int(raw)
        except (ValueError, OverflowError):
            return 0
    if not isinstance(raw, str):
        return 0
    s = raw.strip().replace(",", "")
    if not s:
        return 0
    # Fast path: bare integer
    try:
        return int(s)
    except ValueError:
        pass
    m = _VIEW_RE.search(s)
    if not m:
        return 0
    try:
        base = float(m.group(1))
    except ValueError:
        return 0
    suffix = (m.group(2) or "").upper()
    return int(base * _VIEW_MAGNITUDES.get(suffix, 1))


def search(topic: str, limit: int = 8, max_transcripts: int = 3) -> list[dict]:
    """Search YouTube and optionally fetch transcripts for the top results.

    Args:
        topic: query string
        limit: number of videos to search
        max_transcripts: how many of the top videos to transcribe (each costs $0.0075)
    """
    sys.stderr.write(f"[youtube] search {topic!r} (limit={limit}, transcripts={max_transcripts})\n")
    # Phase 1 — search (apify field name is `searchQueries`, not `searchKeywords`)
    search_body = {
        "searchQueries": [topic],
        "maxResults": limit,
        "maxResultsShorts": 0,
        "maxResultStreams": 0,
        "downloadSubtitles": False,
    }
    search_result = run_monid("apify", "/streamers/youtube-scraper", body=search_body, wait=180, tag="youtube")
    if not search_result:
        return []
    videos = search_result.get("output") or []
    if not isinstance(videos, list):
        return []

    # Sort by view count. Prefer numeric viewCount when present; fall back to
    # parsing viewCountText ("1.2M views", "4.5K") for scrapes that only return
    # the display string.
    def view_sort(v):
        raw = v.get("viewCount")
        if raw not in (None, "", 0):
            return _parse_view_count(raw)
        return _parse_view_count(v.get("viewCountText", ""))

    videos = sorted(videos, key=view_sort, reverse=True)
    sys.stderr.write(f"[youtube] got {len(videos)} videos from search\n")

    # Normalize the search results
    out = []
    for v in videos[:limit]:
        out.append({
            "title": v.get("title", "") or "",
            "url": v.get("url", "") or v.get("videoUrl", "") or "",
            "video_id": v.get("id", "") or v.get("videoId", "") or "",
            "channel_name": v.get("channelName", "") or v.get("author", "") or "",
            "channel_url": v.get("channelUrl", "") or "",
            "view_count": view_sort(v),
            "duration_seconds": v.get("durationSeconds", 0) or 0,
            "published_at": v.get("date", "") or v.get("publishedTime", "") or "",
            "description": (v.get("description") or v.get("text") or "")[:600],
            "transcript": "",
            "transcript_chars": 0,
        })

    # Phase 2 — transcripts for top N
    if max_transcripts > 0:
        top_urls = [v["url"] for v in out[:max_transcripts] if v["url"]]
        for url in top_urls:
            sys.stderr.write(f"[youtube] fetching transcript for {url}\n")
            tr_body = {"youtube_url": url, "language": "en"}
            tr_result = run_monid("apify", "/starvibe/youtube-video-transcript", body=tr_body, wait=240, tag="youtube")
            if not tr_result:
                continue
            tr_items = tr_result.get("output") or []
            if not tr_items or not isinstance(tr_items, list):
                continue
            o = tr_items[0]
            segs = o.get("transcript") or []
            if isinstance(segs, list):
                text = " ".join(s.get("text", "").strip() for s in segs if isinstance(s, dict))
            elif isinstance(segs, str):
                text = segs
            else:
                text = ""
            # Attach back to the matching video in `out`
            for v in out:
                if v["url"] == url:
                    v["transcript"] = text
                    v["transcript_chars"] = len(text)
                    # Refresh metadata from the transcript endpoint (often richer)
                    if not v["title"]:
                        v["title"] = o.get("title", "")
                    if not v["channel_name"]:
                        v["channel_name"] = o.get("channel_name", "")
                    break

    return out


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "Hermes Agent demo"
    vids = search(topic, limit=5, max_transcripts=1)
    for v in vids:
        v_copy = dict(v)
        v_copy["transcript"] = v_copy["transcript"][:500] + "..." if v_copy["transcript"] else ""
        print(json.dumps(v_copy, indent=2, default=str))
