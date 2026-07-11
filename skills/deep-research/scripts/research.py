#!/usr/bin/env python3
"""Deep Research orchestrator — parallel fan-out across 8 data sources, single command.

Project-agnostic. Output defaults to ./research/<slug>/ in the current working
directory. Override with --out=<dir> for project-specific paths.

Usage:
    python3 research.py "Hermes Agent vs OpenClaw"
    python3 research.py "Hermes Agent vs OpenClaw" --depth=deep --days=14
    python3 research.py "Greg Isenberg podcast" --sources=x,youtube,reddit
    python3 research.py "agent-harness" --out=./research/harness/

Sources (all parallel). EVERY source routes through monid (one auth =
MONID_API_KEY, one balance, no per-vendor keys). Native monid endpoints for
X/Reddit/YouTube/Exa; HN/GitHub/Polymarket are proxied through monid's
exa/contents (raw-JSON passthrough).
    reddit        — monid Apify trudax/reddit-scraper-lite (~$0.0057/result)
    hn            — monid exa/contents → HN Algolia JSON (~$0.0022/call)
    polymarket    — monid exa/contents → Gamma search, capped limit=8 (~$0.0022)
    github_repos  — monid exa/contents → api.github.com (~$0.0022/call)
    github_issues — monid exa/contents → api.github.com (~$0.0022/call)
    x             — monid tikhub twitter search (~$0.0015/page)
    youtube       — monid Apify (~$0.005/result + $0.0075/transcript)
    exa           — monid blockrun.ai Exa proxy (~$0.011/call)

Output:
    {out}/research-{date}.json   — full structured evidence
    {out}/research-{date}.md     — human-readable summary

Read the .md first to triage; pull verbatim quotes/numbers from the .json.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Local imports
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from sources import reddit, hackernews, polymarket, github, x_twitter, youtube, exa  # noqa: E402


ALL_SOURCES = ["reddit", "hn", "polymarket", "github_repos", "github_issues", "x", "youtube", "exa"]


def _slug(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s)
    return s[:60].strip("-")


def _date_window(days: int) -> tuple[str, str]:
    to_d = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    from_d = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    return from_d, to_d


def _run_source(name: str, fn, *args, **kwargs) -> tuple[str, list, float, str | None]:
    """Run one source function, capture timing + errors. Always returns a tuple."""
    t0 = time.time()
    try:
        out = fn(*args, **kwargs)
        return name, (out or []), time.time() - t0, None
    except Exception as e:
        return name, [], time.time() - t0, f"{type(e).__name__}: {e}"


def research(
    topic: str,
    depth: str = "default",
    days: int = 30,
    sources: list[str] | None = None,
    yt_transcripts: int = 2,
) -> dict:
    """Run all sources in parallel and collect into a single evidence dict."""
    if sources is None:
        sources = ALL_SOURCES
    sources = [s for s in sources if s in ALL_SOURCES]

    from_date, to_date = _date_window(days)
    sys.stderr.write(f"\n=== Research: {topic!r} | depth={depth} | window={from_date}..{to_date} | sources={sources} ===\n\n")

    limits = {
        "quick": {"reddit": 15, "hn": 15, "polymarket": 8, "github": 6, "x": "quick", "youtube": 5, "exa": 8},
        "default": {"reddit": 25, "hn": 25, "polymarket": 15, "github": 10, "x": "default", "youtube": 8, "exa": 12},
        "deep": {"reddit": 40, "hn": 40, "polymarket": 25, "github": 15, "x": "deep", "youtube": 12, "exa": 18},
    }
    L = limits.get(depth, limits["default"])

    jobs = {}
    with ThreadPoolExecutor(max_workers=len(sources)) as ex:
        if "reddit" in sources:
            jobs[ex.submit(_run_source, "reddit", reddit.search, topic, "month", L["reddit"])] = "reddit"
        if "hn" in sources:
            jobs[ex.submit(_run_source, "hn", hackernews.search, topic, days, L["hn"])] = "hn"
        if "polymarket" in sources:
            jobs[ex.submit(_run_source, "polymarket", polymarket.search, topic, L["polymarket"])] = "polymarket"
        if "github_repos" in sources:
            jobs[ex.submit(_run_source, "github_repos", github.search_repos, topic, L["github"])] = "github_repos"
        if "github_issues" in sources:
            jobs[ex.submit(_run_source, "github_issues", github.search_recent_issues, topic, days, L["github"])] = "github_issues"
        if "x" in sources:
            jobs[ex.submit(_run_source, "x", x_twitter.search, topic, from_date, to_date, L["x"])] = "x"
        if "youtube" in sources:
            jobs[ex.submit(_run_source, "youtube", youtube.search, topic, L["youtube"], yt_transcripts)] = "youtube"
        if "exa" in sources:
            jobs[ex.submit(_run_source, "exa", exa.search, topic, from_date, to_date, L["exa"])] = "exa"

        results = {}
        timings = {}
        errors = {}
        for fut in as_completed(jobs):
            name, out, elapsed, err = fut.result()
            results[name] = out
            timings[name] = round(elapsed, 1)
            if err:
                errors[name] = err
            sys.stderr.write(f"  [{name}] done in {elapsed:.1f}s ({len(out)} items){' — ' + err if err else ''}\n")

    sys.stderr.write(f"\n=== Done. Sources fired: {len(results)}, errored: {len(errors)} ===\n")

    return {
        "topic": topic,
        "depth": depth,
        "date_window": {"from": from_date, "to": to_date, "days": days},
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sources_requested": sources,
        "sources_with_results": [s for s, r in results.items() if r],
        "errors": errors,
        "timings_seconds": timings,
        "counts": {s: len(r) for s, r in results.items()},
        "results": results,
    }


def render_markdown(evidence: dict) -> str:
    """Render a research-ready markdown summary. Brief, no synthesis."""
    topic = evidence["topic"]
    dw = evidence["date_window"]
    counts = evidence["counts"]
    results = evidence["results"]
    out = []
    out.append(f"# Research: {topic}")
    out.append(f"")
    out.append(f"**Window:** {dw['from']} → {dw['to']} ({dw['days']} days)")
    out.append(f"**Generated:** {evidence['generated_at']}")
    out.append(f"**Sources:** {', '.join(f'{s}={c}' for s, c in counts.items() if c)}")
    if evidence.get("errors"):
        out.append(f"**⚠️ Errors:** {evidence['errors']}")
    out.append(f"")
    out.append(f"---")

    # X posts (most useful for direct quoting)
    if results.get("x"):
        out.append(f"\n# X / Twitter ({len(results['x'])} posts)\n")
        for p in sorted(results["x"], key=lambda x: x.get("likes", 0), reverse=True):
            eng = f"{p.get('likes',0)}♥ {p.get('reposts',0)}🔄 {p.get('replies',0)}💬"
            out.append(f"- [{eng} @{p.get('author','?')} {p.get('date','?')}]({p.get('url','')})")
            out.append(f"  > {p.get('text','')[:280].replace(chr(10),' ')}")
            if p.get("why_relevant"):
                out.append(f"  *Why:* {p['why_relevant']}")
            out.append("")

    # Reddit
    if results.get("reddit"):
        out.append(f"\n# Reddit ({len(results['reddit'])} posts)\n")
        for p in sorted(results["reddit"], key=lambda x: x.get("score", 0), reverse=True):
            out.append(f"- [{p.get('score',0)}⬆ {p.get('num_comments',0)}💬 r/{p.get('subreddit','?')}]({p.get('url','')})")
            out.append(f"  **{p.get('title','')}**")
            if p.get("body"):
                out.append(f"  > {p['body'][:250].replace(chr(10),' ')}")
            for c in p.get("comments", [])[:2]:
                out.append(f"  - *[{c.get('score',0)}⬆ @{c.get('author','?')}]*: {c.get('body','')[:200].replace(chr(10),' ')}")
            out.append("")

    # HN
    if results.get("hn"):
        out.append(f"\n# Hacker News ({len(results['hn'])} stories)\n")
        for s in sorted(results["hn"], key=lambda x: x.get("points", 0), reverse=True):
            out.append(f"- [{s.get('points',0)}↑ {s.get('num_comments',0)}💬]({s.get('hn_url','')}) **{s.get('title','')}**")
            if s.get("url") and s["url"] != s.get("hn_url"):
                out.append(f"  Linked: {s['url']}")
            out.append("")

    # GitHub repos
    if results.get("github_repos"):
        out.append(f"\n# GitHub repos ({len(results['github_repos'])} found)\n")
        for r in results["github_repos"]:
            out.append(f"- ⭐{r.get('stars',0):>6} [{r.get('full_name','')}]({r.get('url','')}) — {r.get('description','')[:100]}")
            out.append(f"  pushed: {r.get('pushed_at','')}, lang: {r.get('language','')}, license: {r.get('license','')}")
        out.append("")

    # GitHub issues
    if results.get("github_issues"):
        out.append(f"\n# GitHub recent issues ({len(results['github_issues'])} found)\n")
        for i in sorted(results["github_issues"], key=lambda x: x.get("reactions_total", 0), reverse=True)[:10]:
            out.append(f"- [{i.get('reactions_total',0)}👍 {i.get('comments',0)}💬]({i.get('url','')}) **{i.get('title','')}**")
            out.append(f"  {i.get('repo','')}, {i.get('state','')}, {i.get('created_at','')}")
        out.append("")

    # Polymarket
    if results.get("polymarket"):
        out.append(f"\n# Polymarket ({len(results['polymarket'])} markets)\n")
        for e in results["polymarket"]:
            out.append(f"- [vol=${e.get('volume',0):,.0f}]({e.get('url','')}) **{e.get('title','')}**")
            for m in e.get("markets", [])[:3]:
                outcomes = m.get("outcomes", [])
                prices = m.get("outcome_prices", [])
                if outcomes and prices:
                    pairs = ", ".join(f"{o}={float(p)*100:.0f}%" for o, p in zip(outcomes, prices) if p)
                    out.append(f"  - *{m.get('question','')}*: {pairs}")
            out.append("")

    # YouTube
    if results.get("youtube"):
        out.append(f"\n# YouTube ({len(results['youtube'])} videos)\n")
        for v in results["youtube"]:
            out.append(f"- [{v.get('view_count',0):>8,} views @{v.get('channel_name','?')} {v.get('published_at','')}]({v.get('url','')})")
            out.append(f"  **{v.get('title','')}**")
            if v.get("transcript_chars"):
                out.append(f"  Transcript: {v['transcript_chars']:,} chars (in JSON file)")
            out.append("")

    # Exa
    if results.get("exa"):
        out.append(f"\n# Exa neural web search ({len(results['exa'])} hits)\n")
        for r in results["exa"]:
            out.append(f"- [{r.get('domain','')}]({r.get('url','')}) {r.get('published_date','')}")
            out.append(f"  **{r.get('title','')}**")
            if r.get("highlights"):
                for h in r["highlights"][:2]:
                    out.append(f"  > {h[:250]}")
            out.append("")

    return "\n".join(out)


def main():
    p = argparse.ArgumentParser(
        description="Deep Research orchestrator — 8-source parallel fanout"
    )
    p.add_argument("topic", help="Research topic (free text)")
    p.add_argument("--depth", default="default", choices=["quick", "default", "deep"])
    p.add_argument("--days", type=int, default=30)
    p.add_argument("--sources", default=",".join(ALL_SOURCES),
                   help=f"Comma-separated subset of {ALL_SOURCES}")
    p.add_argument("--yt-transcripts", type=int, default=2,
                   help="How many YouTube videos to transcribe (each ~$0.008)")
    p.add_argument("--out", default="",
                   help="Output dir (default: ./research/<slug>/ relative to CWD)")
    args = p.parse_args()

    sources = [s.strip() for s in args.sources.split(",") if s.strip()]
    slug = _slug(args.topic)
    date_tag = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # Project-agnostic default: ./research/<slug>/ in the current working directory.
    # Projects that want a specific layout pass --out explicitly.
    out_dir = Path(args.out) if args.out else Path.cwd() / "research" / slug
    out_dir.mkdir(parents=True, exist_ok=True)

    evidence = research(args.topic, depth=args.depth, days=args.days,
                        sources=sources, yt_transcripts=args.yt_transcripts)

    json_path = out_dir / f"research-{date_tag}.json"
    md_path = out_dir / f"research-{date_tag}.md"

    json_path.write_text(json.dumps(evidence, indent=2, default=str))
    md_path.write_text(render_markdown(evidence))

    sys.stderr.write(f"\n✓ Saved {json_path}\n")
    sys.stderr.write(f"✓ Saved {md_path}\n")
    sys.stderr.write(f"\nTotal items collected: {sum(evidence['counts'].values())}\n")
    print(str(md_path))  # stdout = the markdown path, for easy chaining


if __name__ == "__main__":
    main()
