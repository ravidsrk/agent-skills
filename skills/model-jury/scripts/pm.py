#!/usr/bin/env python3
# pm.py — tolerant parser for `orca orchestration inbox/check` JSON output.
# The stream interleaves `_heartbeat` lines with real message batches, which breaks naive json.load.
# This strips heartbeat lines, then decodes successive JSON objects and prints each message.
#
# Usage:  orca orchestration inbox --json > inbox.json && python3 pm.py inbox.json
import json, sys

raw = open(sys.argv[1]).read()
# drop heartbeat noise lines
lines = [l for l in raw.splitlines() if l.strip() and '"_heartbeat"' not in l]
raw = ''.join(lines)

dec = json.JSONDecoder()
i = 0
msgs = []
while i < len(raw):
    while i < len(raw) and raw[i] in ' \t\r\n':
        i += 1
    if i >= len(raw):
        break
    try:
        obj, j = dec.raw_decode(raw, i)
        i = j
    except Exception:
        break
    for m in obj.get('result', {}).get('messages', []):
        msgs.append(m)

print('MESSAGES:', len(msgs))
for m in msgs:
    print('=' * 60)
    print('FROM:', m['from_handle'], '| TYPE:', m['type'])
    print('SUBJ:', m['subject'])
    print('BODY:', m['body'])
    print('PAYLOAD:', m['payload'])
