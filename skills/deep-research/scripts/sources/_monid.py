"""Shared monid CLI runner for deep-research sources.

All paid/scrape sources route through the monid catalog so they share one
auth (MONID_API_KEY) and one balance — no per-vendor API keys or credit walls.

Usage:
    from ._monid import run_monid
    result = run_monid("blockrun.ai", "/api/v1/exa/search", body={"query": "..."})
    result = run_monid("tikhub", "/api/v1/twitter/web/fetch_search_timeline",
                       query={"keyword": "..."})

`run_monid` returns the parsed run dict (the full monid envelope with
`output`, `price`, `status`, ...) or None on failure. Callers pull
`result["output"]` and normalize from there.
"""
from __future__ import annotations
import json
import os
import re
import shutil
import subprocess
import sys
import time
from typing import Optional, Union


def _resolve_bin() -> str:
    """Find the monid binary: env override → repo-local node_modules → PATH."""
    env_bin = os.environ.get("MONID_BIN")
    if env_bin and os.path.exists(env_bin):
        return env_bin
    # Common local install locations (in priority order)
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        # ./node_modules/.bin/monid next to the script
        os.path.normpath(os.path.join(here, "..", "..", "node_modules", ".bin", "monid")),
        # repo root node_modules (walk up 4 levels from sources/)
        os.path.normpath(os.path.join(here, "..", "..", "..", "..", "node_modules", ".bin", "monid")),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    found = shutil.which("monid")
    return found or "monid"


MONID_BIN = _resolve_bin()


def _is_transient(envelope: Optional[dict]) -> bool:
    """True if the envelope is an upstream transient failure worth retrying.

    Some monid providers (e.g. tikhub) intermittently return an HTML error page
    instead of JSON under rate-limiting; the CLI surfaces this as an
    `error.message` starting with "Unexpected token '<'". Those are safe to retry.
    """
    if not isinstance(envelope, dict):
        return False
    err = envelope.get("error")
    if isinstance(err, dict):
        msg = str(err.get("message", ""))
        if "Unexpected token '<'" in msg or "<html" in msg or "<!DOCTYPE" in msg:
            return True
        if err.get("code") in ("UNKNOWN", "RATE_LIMIT", "UPSTREAM_ERROR"):
            return True
    return False


def _run_once(cmd: list[str], wait: int, tag: str) -> tuple[Optional[dict], bool]:
    """Single monid invocation → (parsed_envelope_or_None, is_retryable)."""
    env = {**os.environ, "NO_COLOR": "1"}
    try:
        result = subprocess.run(
            cmd, env=env, capture_output=True, text=True, timeout=wait + 30
        )
    except subprocess.TimeoutExpired:
        sys.stderr.write(f"[{tag}/monid] timeout after {wait}s\n")
        return None, True
    except Exception as e:  # noqa: BLE001
        sys.stderr.write(f"[{tag}/monid] error: {e}\n")
        return None, False

    out = result.stdout or ""
    parsed = None
    i = out.find("{")
    if i != -1:
        for candidate in (out, out[i:]):
            try:
                parsed = json.loads(candidate)
                break
            except json.JSONDecodeError:
                continue

    if result.returncode != 0:
        # A non-zero exit may still carry a JSON error envelope on stdout.
        if _is_transient(parsed):
            return None, True
        if isinstance(parsed, dict) and parsed.get("error"):
            sys.stderr.write(f"[{tag}/monid] error body: {str(parsed['error'])[:300]}\n")
        else:
            sys.stderr.write(f"[{tag}/monid] non-zero exit: {(result.stderr or '')[:300]}\n")
        return None, False

    if parsed is None:
        sys.stderr.write(f"[{tag}/monid] unparseable output: {out[:200]}\n")
        return None, True

    # A 200-exit envelope can still wrap a transient upstream error.
    if _is_transient(parsed):
        return None, True
    return parsed, False


def run_monid(
    provider: str,
    endpoint: str,
    body: Optional[dict] = None,
    query: Optional[dict] = None,
    path: Optional[dict] = None,
    wait: int = 90,
    tag: str = "monid",
    retries: int = 2,
) -> Optional[dict]:
    """Execute a monid endpoint and return the parsed result envelope.

    Retries on transient upstream failures (HTML error pages / rate-limits /
    timeouts) with exponential backoff. Non-transient errors fail fast.

    Args:
        provider:  monid provider id (e.g. "blockrun.ai", "tikhub", "apify")
        endpoint:  endpoint path (e.g. "/api/v1/exa/search")
        body:      JSON body → `-i`
        query:     query params → `--query`
        path:      path params → `--path`
        wait:      block up to N seconds for completion (`-w`)
        tag:       label used in stderr log lines
        retries:   extra attempts on transient failure (total tries = retries + 1)
    Returns:
        Parsed monid run dict (has "output", "price", "status", ...) or None.
    """
    cmd = [MONID_BIN, "run", "-p", provider, "-e", endpoint, "-w", str(wait), "--json"]
    if body is not None:
        cmd += ["-i", json.dumps(body)]
    if query is not None:
        cmd += ["--query", json.dumps(query)]
    if path is not None:
        cmd += ["--path", json.dumps(path)]

    for attempt in range(retries + 1):
        parsed, retryable = _run_once(cmd, wait, tag)
        if parsed is not None:
            return parsed
        if not retryable or attempt == retries:
            return None
        backoff = 2 * (attempt + 1)
        sys.stderr.write(f"[{tag}/monid] transient failure, retrying in {backoff}s "
                         f"(attempt {attempt + 2}/{retries + 1})\n")
        time.sleep(backoff)
    return None


def extract_output(result: Optional[dict]):
    """Pull the `output` payload from a monid run envelope (or None)."""
    if not result:
        return None
    return result.get("output")


# --- Generic JSON proxy -----------------------------------------------------
# monid has no native Hacker News / GitHub search endpoint. To keep ALL billing
# on one monid balance (per the "everything through monid" decision), we proxy
# those JSON REST APIs through blockrun.ai's `exa/contents` endpoint, which
# returns the upstream HTTP body VERBATIM (raw bytes, no markdown cleaning) in
# `output.results[0].text`. `fetch_json` json.loads() that directly.
#
# Why not `surf/web/fetch`? That sibling runs a markdown cleaner that collapses
# whitespace inside JSON string values and mangles embedded URLs, producing
# invalid JSON on large/prose-heavy responses (GitHub issue bodies, Polymarket
# Gamma). `exa/contents` is a clean passthrough — verified 2026-06-22 on 166KB
# GitHub issue payloads with no corruption — and cheaper ($0.0022 vs $0.00825).
#
# Size ceiling: exa livecrawl 504s on ~1MB+ responses. Keep page sizes modest
# (GitHub per_page<=15 fine; Polymarket Gamma limit_per_type<=8).

EXA_CONTENTS_PROVIDER = "blockrun.ai"
EXA_CONTENTS_ENDPOINT = "/api/v1/exa/contents"

_JSON_FENCE = re.compile(r"```(?:json)?\s*(.*?)\s*```", re.S)


def _unwrap_json(content: str) -> Optional[Union[dict, list]]:
    """Parse JSON from a text blob — raw first, then fenced, then balanced span."""
    if not content:
        return None
    # 1) raw — content IS json (the exa/contents common case)
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        pass
    # 2) fenced ```json ... ``` block (defensive)
    m = _JSON_FENCE.search(content)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    # 3) first balanced {...} or [...] span
    for opener, closer in (("{", "}"), ("[", "]")):
        start = content.find(opener)
        end = content.rfind(closer)
        if start != -1 and end > start:
            try:
                return json.loads(content[start:end + 1])
            except json.JSONDecodeError:
                continue
    return None


def fetch_json(
    url: str,
    wait: int = 120,
    tag: str = "fetch",
    retries: int = 2,
) -> Optional[Union[dict, list]]:
    """GET a JSON REST API through monid's exa/contents proxy → parsed dict/list.

    Used for sources with no native monid endpoint (Hacker News Algolia, GitHub
    REST, Polymarket Gamma) so their billing still flows through monid.
    `exa/contents` returns the raw response body verbatim (no markdown cleaning),
    so the payload parses with a plain json.loads().
    """
    # exa livecrawl can transiently 504 even on small payloads, so retry the
    # whole call (run_monid's own retry only covers HTML/rate-limit failures).
    for attempt in range(retries + 1):
        result = run_monid(
            EXA_CONTENTS_PROVIDER, EXA_CONTENTS_ENDPOINT,
            body={"urls": [url]}, wait=wait, tag=tag, retries=0,
        )
        output = extract_output(result)
        results = output.get("results") if isinstance(output, dict) else None
        if results:
            text = (results[0] or {}).get("text", "") or ""
            parsed = _unwrap_json(text)
            if parsed is not None:
                return parsed
            sys.stderr.write(f"[{tag}/monid] exa/contents unparseable JSON for {url[:80]}\n")
            return None  # parse failures won't fix on retry
        # No results → likely a livecrawl 504/timeout. Retry with backoff.
        statuses = output.get("statuses") if isinstance(output, dict) else None
        if attempt < retries:
            backoff = 2 * (attempt + 1)
            sys.stderr.write(f"[{tag}/monid] exa/contents no results "
                             f"(statuses={statuses}), retry {attempt + 2}/{retries + 1} "
                             f"in {backoff}s\n")
            time.sleep(backoff)
        else:
            sys.stderr.write(f"[{tag}/monid] exa/contents gave up for {url[:80]} "
                             f"(statuses={statuses})\n")
    return None
