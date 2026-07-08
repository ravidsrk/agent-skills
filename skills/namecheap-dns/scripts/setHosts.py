#!/usr/bin/env python3
"""
Safe Namecheap setHosts wrapper.

Namecheap's setHosts endpoint REPLACES every record on the domain. Any record
you forget to include is silently deleted. This script does the safe pattern:

    getHosts -> merge (add / remove / update) -> setHosts

with strictly contiguous 1..N HostName indexing (Namecheap drops records past
the first gap).

Usage:
    setHosts.py --sld=example --tld=com [--add-json=records.json]
                [--remove='name=www&type=CNAME' ...]
                [--email-type=FWD|MX|NONE|OX] [--dry-run]

Modes:
    --add-json <file>        JSON list of records to add: [{"name","type","address","ttl","mxpref"}]
    --add <spec>             Upsert one record: 'name=docs&type=CNAME&address=x.fly.dev.&ttl=300'
                             Same (name, type) replaces the existing address. Repeat --add for multiple.
    --remove <spec>          Remove records matching (name AND type). Repeat.
    --email-type             Override EmailType (defaults to whatever getHosts returned)
    --dry-run                Print the exact form fields that WOULD be sent. No API call.

Refuses to proceed if:
    - getHosts returned an error (envelope Status != OK)
    - getHosts returned zero records (a zero-record setHosts would wipe zone data
      if a prior read failed; require --force-empty if you really want that).

Env vars (all required):
    NAMECHEAP_API_KEY, NAMECHEAP_API_USER
    CLIENT_IP is optional; defaults to api.ipify.org lookup at runtime.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any


NC_ENDPOINT = "https://api.namecheap.com/xml.response"


def _env(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        print(f"ERROR: env var {name} is required", file=sys.stderr)
        sys.exit(2)
    return v


def _client_ip() -> str:
    ip = os.environ.get("CLIENT_IP", "").strip()
    if ip:
        return ip
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=8) as r:
            return r.read().decode().strip()
    except Exception as e:
        print(f"ERROR: could not determine outbound IP: {e}", file=sys.stderr)
        sys.exit(3)


def _strip_ns(root: ET.Element) -> ET.Element:
    for el in root.iter():
        if "}" in el.tag:
            el.tag = el.tag.split("}", 1)[1]
    return root


def _envelope_ok(root: ET.Element) -> tuple[bool, str]:
    status = root.attrib.get("Status", "").upper()
    if status != "OK":
        err = ""
        for e in root.iter("Error"):
            err = (e.text or "").strip()
            break
        return False, err or f"envelope Status={status!r}"
    return True, ""


def get_hosts(sld: str, tld: str) -> dict[str, Any]:
    """Return {'email_type': str, 'hosts': [{'name','type','address','ttl','mxpref'}]}."""
    params = {
        "ApiUser":  _env("NAMECHEAP_API_USER"),
        "ApiKey":   _env("NAMECHEAP_API_KEY"),
        "UserName": _env("NAMECHEAP_API_USER"),
        "ClientIp": _client_ip(),
        "Command":  "namecheap.domains.dns.getHosts",
        "SLD":      sld,
        "TLD":      tld,
    }
    url = NC_ENDPOINT + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=20) as r:
        raw = r.read().decode()
    try:
        root = _strip_ns(ET.fromstring(raw))
    except ET.ParseError as e:
        print(f"ERROR: malformed getHosts XML: {e}", file=sys.stderr)
        sys.exit(4)
    ok, err = _envelope_ok(root)
    if not ok:
        print(f"ERROR: Namecheap getHosts failed: {err}", file=sys.stderr)
        sys.exit(4)

    dhr = root.find(".//DomainDNSGetHostsResult")
    email_type = dhr.attrib.get("EmailType", "") if dhr is not None else ""
    hosts = []
    for h in root.iter("host"):
        a = h.attrib
        hosts.append({
            "name":    a.get("Name", ""),
            "type":    (a.get("Type", "") or "").upper(),
            "address": a.get("Address", ""),
            "ttl":     a.get("TTL", "300"),
            "mxpref":  a.get("MXPref", "10"),
        })
    return {"email_type": email_type, "hosts": hosts}


def _parse_kv(spec: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for chunk in spec.split("&"):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "=" not in chunk:
            print(f"ERROR: bad --add/--remove spec (want key=val): {spec!r}", file=sys.stderr)
            sys.exit(2)
        k, v = chunk.split("=", 1)
        out[k.strip().lower()] = v.strip()
    return out


def _normalize(h: dict[str, Any]) -> dict[str, str]:
    return {
        "name":    h.get("name", ""),
        "type":    (h.get("type", "") or "").upper(),
        "address": h.get("address", ""),
        "ttl":     str(h.get("ttl", "300")),
        "mxpref":  str(h.get("mxpref", "10")),
    }


def merge(existing: list[dict], adds: list[dict], removes: list[dict]) -> list[dict]:
    # Remove first
    def matches_remove(r: dict, rm: dict) -> bool:
        if "name" in rm and rm["name"].lower() != r["name"].lower():
            return False
        if "type" in rm and rm["type"].upper() != r["type"].upper():
            return False
        if "address" in rm and rm["address"] != r["address"]:
            return False
        return True

    kept = [r for r in existing if not any(matches_remove(r, rm) for rm in removes)]

    # Add / upsert: same (name, type) is an update (new address replaces old).
    # Matching on address too would leave duplicate CNAMEs when retargeting.
    def same_key(a: dict, b: dict) -> bool:
        return (a["name"].lower() == b["name"].lower()
                and a["type"].upper() == b["type"].upper())

    out = list(kept)
    for add in adds:
        add = _normalize(add)
        replaced = False
        for i, existing_rec in enumerate(out):
            if same_key(existing_rec, add):
                out[i] = add
                replaced = True
                break
        if not replaced:
            out.append(add)
    return out


def build_form(sld: str, tld: str, records: list[dict], email_type: str, client_ip: str) -> list[tuple[str, str]]:
    """Contiguous HostName1..HostNameN. Any gap = Namecheap drops from that point on."""
    form: list[tuple[str, str]] = [
        ("ApiUser",  _env("NAMECHEAP_API_USER")),
        ("ApiKey",   _env("NAMECHEAP_API_KEY")),
        ("UserName", _env("NAMECHEAP_API_USER")),
        ("ClientIp", client_ip),
        ("Command",  "namecheap.domains.dns.setHosts"),
        ("SLD",      sld),
        ("TLD",      tld),
    ]
    if email_type:
        form.append(("EmailType", email_type))

    for i, r in enumerate(records, start=1):
        r = _normalize(r)
        form.append((f"HostName{i}",   r["name"]))
        form.append((f"RecordType{i}", r["type"]))
        form.append((f"Address{i}",    r["address"]))
        form.append((f"TTL{i}",        r["ttl"]))
        if r["type"] == "MX":
            form.append((f"MXPref{i}", r["mxpref"]))
    return form


def redact(form: list[tuple[str, str]]) -> list[tuple[str, str]]:
    return [(k, ("***" if k == "ApiKey" else v)) for k, v in form]


def call_set_hosts(form: list[tuple[str, str]]) -> str:
    data = urllib.parse.urlencode(form).encode()
    req = urllib.request.Request(NC_ENDPOINT, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sld", required=True)
    ap.add_argument("--tld", required=True)
    ap.add_argument("--add", action="append", default=[],
                    help="Record spec: 'name=docs&type=CNAME&address=x.fly.dev.&ttl=300'. Repeatable.")
    ap.add_argument("--add-json", default=None,
                    help="Path to a JSON file with a list of record objects.")
    ap.add_argument("--remove", action="append", default=[],
                    help="Match spec: 'name=www&type=CNAME'. Repeatable.")
    ap.add_argument("--email-type", default=None,
                    help="EmailType override: FWD|MX|NONE|OX. Defaults to what getHosts returned.")
    ap.add_argument("--dry-run", action="store_true", help="Print the request; don't send it.")
    ap.add_argument("--force-empty", action="store_true",
                    help="Allow proceeding with zero final records (destructive).")
    args = ap.parse_args()

    current = get_hosts(args.sld, args.tld)

    if not current["hosts"] and not args.force_empty and not (args.add or args.add_json):
        print("ERROR: getHosts returned zero records. Refusing to setHosts an empty list "
              "(would wipe the zone if the read failed silently). Pass --force-empty to override.",
              file=sys.stderr)
        return 5

    adds: list[dict] = []
    if args.add_json:
        try:
            with open(args.add_json) as f:
                loaded = json.load(f)
        except Exception as e:
            print(f"ERROR: reading --add-json: {e}", file=sys.stderr)
            return 2
        if not isinstance(loaded, list):
            print("ERROR: --add-json must contain a JSON list of records", file=sys.stderr)
            return 2
        adds.extend(loaded)
    for spec in args.add:
        adds.append(_parse_kv(spec))

    removes = [_parse_kv(spec) for spec in args.remove]

    final_records = merge(current["hosts"], adds, removes)

    if not final_records and not args.force_empty:
        print("ERROR: merge produced zero records. Refusing to send an empty setHosts. "
              "Pass --force-empty if you really mean to wipe the zone.",
              file=sys.stderr)
        return 5

    email_type = args.email_type if args.email_type is not None else current["email_type"]
    client_ip = _client_ip()
    form = build_form(args.sld, args.tld, final_records, email_type, client_ip)

    print(f"Current records at {args.sld}.{args.tld}: {len(current['hosts'])}")
    print(f"After merge:                              {len(final_records)}")
    print(f"EmailType:                                {email_type or '(default)'}")
    print()
    print("Records that would be sent (contiguous HostName1..HostNameN):")
    for i, r in enumerate(final_records, start=1):
        rn = _normalize(r)
        mx = f"  MXPref={rn['mxpref']}" if rn["type"] == "MX" else ""
        print(f"  {i:>3}. {rn['type']:<6} {rn['name']:<30} -> {rn['address']}  ttl={rn['ttl']}{mx}")
    print()

    if args.dry_run:
        print("[DRY-RUN] would POST the following form fields (ApiKey redacted):")
        for k, v in redact(form):
            print(f"  {k}={v}")
        return 0

    print("Sending setHosts...")
    raw = call_set_hosts(form)
    try:
        root = _strip_ns(ET.fromstring(raw))
    except ET.ParseError as e:
        print(f"ERROR: malformed setHosts XML: {e}", file=sys.stderr)
        print(raw, file=sys.stderr)
        return 6
    ok, err = _envelope_ok(root)
    if not ok:
        print(f"ERROR: Namecheap setHosts failed: {err}", file=sys.stderr)
        print(raw, file=sys.stderr)
        return 6

    # Confirm IsSuccess="true" on the actual command result
    result_ok = False
    for r in root.iter("DomainDNSSetHostsResult"):
        result_ok = r.attrib.get("IsSuccess", "").lower() == "true"
        break
    if not result_ok:
        print("ERROR: setHosts envelope OK but DomainDNSSetHostsResult IsSuccess != true", file=sys.stderr)
        print(raw, file=sys.stderr)
        return 6

    print(f"(OK) setHosts succeeded; {len(final_records)} records now live.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
