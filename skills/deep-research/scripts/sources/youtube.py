"""YouTube research via monid Apify scrapers.

Two phases:
1. Search YouTube for the topic (apify//streamers/youtube-scraper, $0.0045/result)
2. Pull full transcripts for the top N results (apify//starvibe/youtube-video-transcript, $0.0075/result)

The transcript endpoint often returns 8K+ word transcripts — game-changer
for any research where a podcast or interview is the primary source.
"""
from __future__ import annotations
import json
import os
import subprocess
import sys
from typing import Optional


from ._monid import MONID_BIN


def _run_monid(endpoint: str, body: dict, wait: int = 180) -> Optional[dict]:
    cmd = [
        MONID_BIN, "run",
        "-p", "apify",
        "-e", endpoint,
        "-i", json.dumps(body),
        "-w", str(wait),
        "--json",
    ]
    env = {**os.environ, "NO_COLOR": "1"}
    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=wait + 30)
        if result.returncode != 0:
            sys.stderr.write(f"[youtube/monid] non-zero exit on {endpoint}: {result.stderr[:400]}\n")
            return None
        out = result.stdout
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            i = out.find("{")
            if i == -1:
                return None
            return json.loads(out[i:])
    except subprocess.TimeoutExpired:
        sys.stderr.write(f"[youtube/monid] timeout on {endpoint}\n")
        return None
    except Exception as e:
        sys.stderr.write(f"[youtube/monid] error on {endpoint}: {e}\n")
        return None


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
    search_result = _run_monid("/streamers/youtube-scraper", search_body, wait=180)
    if not search_result:
        return []
    videos = search_result.get("output") or []
    if not isinstance(videos, list):
        return []

    # Sort by view count + filter low-quality
    def view_sort(v):
        try:
            return int(v.get("viewCount") or v.get("viewCountText", "0").replace(",", "").replace(" views", "") or 0)
        except (ValueError, AttributeError):
            return 0

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
            tr_result = _run_monid("/starvibe/youtube-video-transcript", tr_body, wait=240)
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
