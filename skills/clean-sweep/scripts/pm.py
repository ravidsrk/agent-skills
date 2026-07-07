#!/usr/bin/env python3
"""pm.py — tolerant parser for `orca orchestration inbox/check` JSON output.

The stream interleaves `_heartbeat` messages with real message batches, which breaks naive
`json.load`. This walks the stream with a `JSONDecoder`, filters heartbeats by their top-level
`type` field (NOT by substring on the raw text — a body that happens to mention the word
`_heartbeat` used to get its line dropped, corrupting the surrounding JSON), and prints each
real message.

Usage:
    orca orchestration inbox --json > inbox.json
    python3 pm.py inbox.json             # human-readable
    python3 pm.py --json inbox.json      # machine-readable (JSON array)

Exit codes:
    0 — parsed cleanly.
    1 — usage / I/O error.
    2 — parsed but dropped one or more malformed regions (details on stderr).
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def _next_object_start(text: str, start: int) -> int:
    """Return the index of the next `{` at or after `start`, or len(text) if none."""
    idx = text.find("{", start)
    return idx if idx != -1 else len(text)


def parse_stream(raw: str) -> tuple[list[dict[str, Any]], int]:
    """Walk `raw` with a JSONDecoder, returning (messages, dropped_regions).

    Non-heartbeat messages are returned in order. Malformed regions are skipped with a
    resync to the next `{`, and the count of skipped regions is returned so the caller
    can exit non-zero if any messages might have been dropped.
    """
    decoder = json.JSONDecoder()
    length = len(raw)
    i = 0
    messages: list[dict[str, Any]] = []
    dropped_regions = 0

    while i < length:
        # skip whitespace
        while i < length and raw[i] in " \t\r\n":
            i += 1
        if i >= length:
            break

        try:
            obj, j = decoder.raw_decode(raw, i)
        except json.JSONDecodeError as exc:
            dropped_regions += 1
            # resync: hop to the next `{` past the failure so we can keep parsing.
            resync = _next_object_start(raw, i + 1)
            context = raw[i : i + 80].replace("\n", " ")
            print(
                f"pm.py: JSON decode error at byte {i} ({exc.msg}); "
                f"resyncing to byte {resync}. Context: {context!r}",
                file=sys.stderr,
            )
            if resync <= i:
                break
            i = resync
            continue

        i = j

        if not isinstance(obj, dict):
            continue

        # Filter heartbeats by their top-level `type` field (not by raw-text substring).
        # A batch is `{ "result": { "messages": [...] } }`; a heartbeat is
        # `{ "type": "_heartbeat", ... }`.
        if obj.get("type") == "_heartbeat":
            continue

        result = obj.get("result")
        if not isinstance(result, dict):
            continue
        for m in result.get("messages", []) or []:
            if isinstance(m, dict) and m.get("type") != "_heartbeat":
                messages.append(m)

    return messages, dropped_regions


def print_human(messages: list[dict[str, Any]]) -> None:
    print("MESSAGES:", len(messages))
    for m in messages:
        print("=" * 60)
        print("FROM:", m.get("from_handle", "<missing>"), "| TYPE:", m.get("type", "<missing>"))
        print("SUBJ:", m.get("subject", "<missing>"))
        print("BODY:", m.get("body", "<missing>"))
        print("PAYLOAD:", m.get("payload", "<missing>"))


def print_json(messages: list[dict[str, Any]]) -> None:
    json.dump(messages, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="pm.py",
        description="Tolerant parser for orca orchestration inbox/check JSON output.",
    )
    parser.add_argument(
        "path",
        help="Path to a JSON file produced by `orca orchestration inbox --json`.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the messages as a JSON array on stdout (machine-readable).",
    )
    args = parser.parse_args(argv)

    try:
        with open(args.path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        print(f"pm.py: could not read {args.path}: {exc}", file=sys.stderr)
        return 1

    messages, dropped = parse_stream(raw)

    if args.json:
        print_json(messages)
    else:
        print_human(messages)

    if dropped:
        print(
            f"pm.py: parsed {len(messages)} messages but dropped {dropped} "
            f"malformed region(s); exit 2.",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
