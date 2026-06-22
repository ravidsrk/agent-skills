#!/bin/bash
# Export a Cloudflare zone to a YAML manifest (DNS-as-code).
# Usage: ./dns-export.sh <domain> [--output=<path>] [--format=yaml|json|terraform|zonefile]
#
# Useful for:
#   - Source-controlling DNS so changes go through PR review
#   - Backup before risky changes
#   - Migration to a different DNS provider later
#   - Generating Terraform stubs from current state
#
# Default output: .dns-state/<domain>/zone.<format>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain> [--output=<path>] [--format=yaml|json|terraform|zonefile]"; exit 1; }
shift || true

DIR="$(state_dir "$DOMAIN")"
FORMAT="yaml"
OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --output=*) OUTPUT="${1#*=}" ;;
    --format=*) FORMAT="${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

case "$FORMAT" in
  yaml)      [ -z "$OUTPUT" ] && OUTPUT="${DIR}/zone.yaml" ;;
  json)      [ -z "$OUTPUT" ] && OUTPUT="${DIR}/zone.json" ;;
  zonefile)  [ -z "$OUTPUT" ] && OUTPUT="${DIR}/zone.bind" ;;
  terraform) [ -z "$OUTPUT" ] && OUTPUT="${DIR}/zone.tf" ;;
  *) echo "Unknown format: $FORMAT (use yaml, json, zonefile, or terraform)" >&2; exit 1 ;;
esac

require_env

ZONE_ID=$(cf_zone_id "$DOMAIN")
[ -z "$ZONE_ID" ] && { echo "ERROR: zone $DOMAIN not in Cloudflare" >&2; exit 1; }

# Save raw API responses to disk so python can read them as files
# (avoids JSON-in-shell-string escaping issues)
mkdir -p "${DIR}/.export-raw"
cf_api GET "/zones/${ZONE_ID}"                                         > "${DIR}/.export-raw/zone.json"
cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=500"                > "${DIR}/.export-raw/records.json"
cf_api GET "/zones/${ZONE_ID}/settings"                                > "${DIR}/.export-raw/settings.json"
cf_api GET "/zones/${ZONE_ID}/rulesets"                                > "${DIR}/.export-raw/rulesets.json"
cf_api GET "/zones/${ZONE_ID}/dnssec"                                  > "${DIR}/.export-raw/dnssec.json"

DOMAIN="$DOMAIN" \
RAW_DIR="${DIR}/.export-raw" \
OUTPUT="$OUTPUT" \
FORMAT="$FORMAT" \
python3 <<'PYEOF'
import json, os, datetime, sys

domain = os.environ['DOMAIN']
raw = os.environ['RAW_DIR']
output = os.environ['OUTPUT']
fmt = os.environ['FORMAT']

zone     = json.load(open(f"{raw}/zone.json"))['result']
records  = json.load(open(f"{raw}/records.json"))['result']
settings = json.load(open(f"{raw}/settings.json")).get('result', [])
rulesets = json.load(open(f"{raw}/rulesets.json")).get('result', [])
dnssec   = json.load(open(f"{raw}/dnssec.json")).get('result', {})

# Sort records by type then name for deterministic output
records.sort(key=lambda r: (r['type'], r['name']))

now_iso = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

def short_name(name):
    return '@' if name == domain else name.removesuffix(f".{domain}")

# ---------------------------------------------------------------------------
if fmt == 'yaml':
    SETTING_KEYS = {
        'ssl', 'always_use_https', 'automatic_https_rewrites', 'min_tls_version',
        'tls_1_3', 'opportunistic_encryption', '0rtt', 'http3', 'websockets',
        'ipv6', 'email_obfuscation', 'browser_check', 'security_level',
        'challenge_ttl', 'privacy_pass', 'security_header'
    }
    settings_d = {s['id']: s.get('value') for s in settings if s.get('id') in SETTING_KEYS}

    out = []
    out.append(f"# Cloudflare zone export — {domain}")
    out.append(f"# Exported: {now_iso}")
    out.append(f"# Zone ID: {zone['id']} (status={zone['status']}, plan={zone['plan']['name']})")
    out.append("")
    out.append(f"domain: {domain}")
    out.append(f"plan: {json.dumps(zone['plan']['name'])}")
    out.append("nameservers:")
    for ns in zone.get('name_servers', []): out.append(f"  - {ns}")
    out.append("original_nameservers:")
    for ns in zone.get('original_name_servers', []): out.append(f"  - {ns}")

    out.append("")
    out.append("settings:")
    for k in sorted(settings_d):
        v = settings_d[k]
        if isinstance(v, dict):
            out.append(f"  {k}:")
            def emit(d, indent):
                for sk, sv in d.items():
                    if isinstance(sv, dict):
                        out.append(f"{'  '*indent}{sk}:")
                        emit(sv, indent+1)
                    else:
                        out.append(f"{'  '*indent}{sk}: {json.dumps(sv)}")
            emit(v, 2)
        else:
            out.append(f"  {k}: {json.dumps(v)}")

    out.append("")
    out.append("dnssec:")
    out.append(f"  status: {dnssec.get('status','disabled')}")
    if dnssec.get('status') == 'active':
        out.append(f"  key_tag: {dnssec.get('key_tag')}")
        out.append(f"  algorithm: {dnssec.get('algorithm')}")
        out.append(f"  digest_type: {dnssec.get('digest_type')}")
        out.append(f"  digest: {json.dumps(dnssec.get('digest'))}")
        out.append(f"  ds_record: {json.dumps(dnssec.get('ds'))}")

    out.append("")
    out.append("records:")
    for r in records:
        out.append(f"  - type: {r['type']}")
        out.append(f"    name: {short_name(r['name'])}")
        out.append(f"    content: {json.dumps(r['content'])}")
        out.append(f"    ttl: {r['ttl']}")
        if r['type'] in ('A','AAAA','CNAME'):
            out.append(f"    proxied: {str(r.get('proxied', False)).lower()}")
        if r['type'] == 'MX':
            out.append(f"    priority: {r.get('priority', 10)}")
        if r['type'] == 'CAA':
            d = r.get('data', {})
            out.append(f"    data:")
            out.append(f"      flags: {d.get('flags',0)}")
            out.append(f"      tag: {d.get('tag')}")
            out.append(f"      value: {json.dumps(d.get('value',''))}")
        if r.get('comment'):
            out.append(f"    comment: {json.dumps(r['comment'])}")

    out.append("")
    out.append("rulesets:")
    for rs in rulesets:
        out.append(f"  - phase: {rs.get('phase')}")
        out.append(f"    kind: {rs.get('kind')}")
        out.append(f"    name: {json.dumps(rs.get('name',''))}")
        out.append(f"    id: {rs.get('id')}")

    open(output, 'w').write('\n'.join(out) + '\n')
    print(f"  🟢 Exported {len(records)} records, {len(settings_d)} settings, {len(rulesets)} rulesets")
    print(f"     to: {output}")

# ---------------------------------------------------------------------------
elif fmt == 'json':
    out = {
        'domain': domain,
        'zone_id': zone['id'],
        'status': zone['status'],
        'plan': zone['plan']['name'],
        'nameservers': zone.get('name_servers', []),
        'records': records,
        'settings': {s['id']: s.get('value') for s in settings},
        'rulesets': [{k: rs.get(k) for k in ('id','name','phase','kind','version')} for rs in rulesets],
        'dnssec': dnssec,
        'exported_at': now_iso,
    }
    open(output, 'w').write(json.dumps(out, indent=2, default=str))
    print(f"  🟢 Exported to {output}")

# ---------------------------------------------------------------------------
elif fmt == 'zonefile':
    lines = [
        f";; Cloudflare zone export — {domain}",
        f";; Exported: {now_iso}",
        "",
        f"$ORIGIN {domain}.",
        f"$TTL 300",
        "",
    ]
    for r in records:
        short = short_name(r['name'])
        rtype = r['type']
        if rtype == 'MX':
            lines.append(f"{short:<30} {r['ttl']:<6} IN MX {r.get('priority',10)} {r['content']}.")
        elif rtype == 'TXT':
            lines.append(f"{short:<30} {r['ttl']:<6} IN TXT {r['content']}")
        elif rtype == 'CAA':
            d = r.get('data', {})
            lines.append(f"{short:<30} {r['ttl']:<6} IN CAA {d.get('flags',0)} {d.get('tag')} \"{d.get('value','')}\"")
        elif rtype in ('CNAME','NS'):
            lines.append(f"{short:<30} {r['ttl']:<6} IN {rtype} {r['content']}.")
        elif rtype in ('A','AAAA'):
            lines.append(f"{short:<30} {r['ttl']:<6} IN {rtype} {r['content']}")
        else:
            lines.append(f"{short:<30} {r['ttl']:<6} IN {rtype} {r['content']}")
    open(output, 'w').write('\n'.join(lines) + '\n')
    print(f"  🟢 Exported BIND zonefile → {output}")

# ---------------------------------------------------------------------------
elif fmt == 'terraform':
    safe = domain.replace('.', '_')
    lines = [
        f"# Cloudflare zone — {domain} (auto-generated by the skill cloudflare-dns skill)",
        f"# To import: terraform import cloudflare_zone.{safe} {zone['id']}",
        "",
        f'resource "cloudflare_zone" "{safe}" {{',
        f'  zone = "{domain}"',
        '}',
        '',
    ]
    for r in records:
        if r['type'] in ('SOA','NS') and r['name'] == domain:
            continue
        rname = short_name(r['name'])
        slug = f"{r['type'].lower()}_{rname.replace('@','apex').replace('*','wildcard').replace('.','_').replace('_','-')}"
        lines.append(f'resource "cloudflare_record" "{slug}" {{')
        lines.append(f'  zone_id = cloudflare_zone.{safe}.id')
        lines.append(f'  name    = "{rname}"')
        lines.append(f'  type    = "{r["type"]}"')
        if r['type'] == 'MX':
            lines.append(f'  priority = {r.get("priority",10)}')
        lines.append(f'  value   = {json.dumps(r["content"])}')
        lines.append(f'  ttl     = {r["ttl"]}')
        if r['type'] in ('A','AAAA','CNAME'):
            lines.append(f'  proxied = {str(r.get("proxied", False)).lower()}')
        lines.append('}')
        lines.append('')
    open(output, 'w').write('\n'.join(lines) + '\n')
    print(f"  🟢 Exported Terraform → {output}")

PYEOF
