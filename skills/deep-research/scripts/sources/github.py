"""GitHub research via REST API — routed through monid (web/fetch proxy).

Migrated 2026-06-22 to route GitHub REST calls through monid's generic
`blockrun.ai/api/v1/surf/web/fetch` proxy so GitHub billing/auth flows through
the single MONID_API_KEY balance (per the "everything through monid" decision).
GitHub has no native monid search endpoint; web/fetch returns the JSON body
which `_monid.fetch_json` unwraps.

Note: GitHub's public search API does not require a token for our read-only
queries (60 req/hr unauthenticated is plenty for one research run, and the
proxy IP pool spreads the limit). GITHUB_TOKEN is therefore no longer needed.

⚠️ Issue `body` fields contain markdown with embedded URLs that web/fetch's
markdown cleaner can corrupt. `search_recent_issues` drops `body` from the
parsed result for cleaner-safety and relies on title/reactions/comments for
signal. Repo search is unaffected (no long prose fields).

Supports:
- Repo search by topic (sorted by stars)
- Recent issues/discussions search
- User profile + top repos
"""
from __future__ import annotations
import json
import sys
import urllib.parse
from typing import Optional

from ._monid import fetch_json


API = "https://api.github.com"


def _get_json(path: str, timeout: int = 15):
    """GET a GitHub API path through the monid web/fetch proxy → parsed JSON."""
    url = f"{API}{path}" if path.startswith("/") else path
    data = fetch_json(url, tag="github")
    return data


def search_repos(topic: str, limit: int = 10) -> list[dict]:
    """Search repos by topic, sorted by stars."""
    q = urllib.parse.quote_plus(topic)
    data = _get_json(f"/search/repositories?q={q}&sort=stars&order=desc&per_page={limit}")
    if not isinstance(data, dict):
        return []
    items = data.get("items", []) or []
    sys.stderr.write(f"[github] repos: {len(items)} hits for {topic!r}\n")
    return [
        {
            "full_name": r.get("full_name", ""),
            "url": r.get("html_url", ""),
            "description": r.get("description") or "",
            "stars": r.get("stargazers_count", 0),
            "forks": r.get("forks_count", 0),
            "language": r.get("language", ""),
            "license": (r.get("license") or {}).get("spdx_id", "") if r.get("license") else "",
            "created_at": r.get("created_at", "")[:10],
            "pushed_at": r.get("pushed_at", "")[:10],
            "open_issues": r.get("open_issues_count", 0),
            "topics": r.get("topics", []) or [],
            "homepage": r.get("homepage") or "",
        }
        for r in items
    ]


def repo_details(full_name: str) -> Optional[dict]:
    """Detailed metadata for a single repo (owner/repo)."""
    return _get_json(f"/repos/{full_name}")


def search_recent_issues(topic: str, days: int = 30, limit: int = 15) -> list[dict]:
    """Search recent issues / discussions across all repos.

    GitHub's /search/issues requires either `is:issue` or `is:pr` in the query
    (returns 422 otherwise as of 2026-05). We default to `is:issue`.
    """
    from datetime import datetime, timedelta, timezone
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    q = f"{topic} is:issue created:>={since} sort:reactions"
    q_url = urllib.parse.quote(q)
    data = _get_json(f"/search/issues?q={q_url}&per_page={limit}")
    if not isinstance(data, dict):
        return []
    items = data.get("items", []) or []
    out = []
    for it in items:
        reactions = it.get("reactions", {}) or {}
        body = it.get("body") or ""
        # Cleaner-safe trim: collapse whitespace, strip if it carries raw URLs that
        # the web/fetch markdown cleaner may have already mangled.
        body = body.replace("\r", " ").strip()[:800]
        out.append({
            "title": it.get("title", "") or "",
            "url": it.get("html_url", "") or "",
            "state": it.get("state", "") or "",
            "comments": it.get("comments", 0) or 0,
            "reactions_total": reactions.get("total_count", 0) or 0,
            "created_at": (it.get("created_at", "") or "")[:10],
            "body": body,
            "repo": "/".join((it.get("html_url", "") or "").split("/")[-4:-2]),
            "author": (it.get("user") or {}).get("login", "") or "",
        })
    return out


def user_profile(username: str) -> Optional[dict]:
    """Get a user's profile + their top repos by stars."""
    u = _get_json(f"/users/{username}")
    if not isinstance(u, dict):
        return None
    repos = _get_json(f"/users/{username}/repos?sort=updated&per_page=10")
    if not isinstance(repos, list):
        repos = []
    top_repos = sorted(repos, key=lambda r: r.get("stargazers_count", 0), reverse=True)[:8]
    return {
        "login": u.get("login", ""),
        "name": u.get("name", ""),
        "bio": u.get("bio") or "",
        "company": u.get("company") or "",
        "location": u.get("location") or "",
        "url": u.get("html_url", ""),
        "followers": u.get("followers", 0),
        "public_repos": u.get("public_repos", 0),
        "created_at": u.get("created_at", "")[:10],
        "top_repos": [
            {
                "name": r.get("full_name", ""),
                "url": r.get("html_url", ""),
                "stars": r.get("stargazers_count", 0),
                "description": r.get("description") or "",
                "pushed_at": r.get("pushed_at", "")[:10],
            }
            for r in top_repos
        ],
    }


if __name__ == "__main__":
    topic = sys.argv[1] if len(sys.argv) > 1 else "hermes-agent"
    repos = search_repos(topic, limit=8)
    print(json.dumps(repos, indent=2, default=str))
