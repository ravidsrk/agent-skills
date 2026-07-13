#!/bin/bash
# Read-only audit of a domain's DNS state.
# Usage: ./audit.sh <domain>
#
# Outputs:
#   - registrar nameservers
#   - all host records at the registrar (authoritative)
#   - whether Cloudflare zone exists
#   - if zone exists, all records there too
#   - delta between the two
#
# Writes JSON to .dns-state/<domain>/audit-pre.json on first run
# (won't overwrite — that file is the migration baseline).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

REQUIRE_NAMECHEAP=1 require_env

read -r SLD TLD <<< "$(domain_split "$DOMAIN")"
DIR="$(state_dir "$DOMAIN")"

echo "═══════════════════════════════════════════════════════════════"
echo "  DNS Audit: $DOMAIN"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Registrar nameservers
echo "▸ Namecheap nameservers:"
NC_NS=$(nc_get_nameservers "$SLD" "$TLD")
echo "$NC_NS" | sed 's/^/    /'
echo ""

# 2. Registrar host records
echo "▸ Namecheap host records:"
NC_XML=$(nc_get_hosts "$SLD" "$TLD")
NC_JSON=$(echo "$NC_XML" | nc_hosts_to_json)
echo "$NC_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f'    EmailType: {d[\"email_type\"]}  ({len(d[\"hosts\"])} records)')
for h in d['hosts']:
    name = h['name'] if h['name'] != '@' else '(apex)'
    print(f'    {h[\"type\"]:<5} {name:<40} → {h[\"address\"]}')"
echo ""

# Save baseline if first run
if [ ! -f "${DIR}/audit-pre.json" ]; then
  python3 -c "
import json
data = {
  'domain': '$DOMAIN',
  'nameservers': '''$NC_NS'''.strip().split('\n'),
  'records': $NC_JSON,
}
with open('${DIR}/audit-pre.json','w') as f:
  json.dump(data, f, indent=2)
print('    [saved baseline → ${DIR}/audit-pre.json]')"
fi

# 3. Cloudflare zone state
echo "▸ Cloudflare zone:"
ZONE_RESP=$(cf_api GET "/zones?name=${DOMAIN}")
cf_assert_success "$ZONE_RESP" "list zones"
ZONE_COUNT=$(echo "$ZONE_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['result_info']['count'])")

if [ "$ZONE_COUNT" = "0" ]; then
  echo "    [not yet in Cloudflare]"
  echo ""
  echo "  → next step: ./migrate.sh $DOMAIN create"
  exit 0
fi

ZONE_ID=$(echo "$ZONE_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0]['id'])")
ZONE_DETAIL=$(echo "$ZONE_RESP" | python3 -c "
import json,sys
z = json.load(sys.stdin)['result'][0]
print(f'    status:      {z[\"status\"]}')
print(f'    plan:        {z[\"plan\"][\"name\"]}')
print(f'    nameservers: {\", \".join(z.get(\"name_servers\", []))}')
print(f'    created:     {z[\"created_on\"][:19]}')
")
echo "$ZONE_DETAIL"
echo "    zone_id:     ${ZONE_ID:0:8}***"
echo ""

# 4. Cloudflare records
echo "▸ Cloudflare records:"
CF_RECORDS=$(cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=100")
cf_assert_success "$CF_RECORDS" "list records"
echo "$CF_RECORDS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
recs = d.get('result', [])
print(f'    ({len(recs)} records)')
for r in recs:
    n = r['name']
    suffix = '$DOMAIN'
    n = '(apex)' if n == suffix else n.rsplit('.'+suffix,1)[0] if n.endswith('.'+suffix) else n
    proxy = '🟠' if r.get('proxied') else '⚪'
    extra = f' priority={r[\"priority\"]}' if r['type'] == 'MX' else ''
    print(f'    {r[\"type\"]:<5} {n:<40} → {r[\"content\"]}{extra} {proxy}')"
echo ""

# 5. Delta
echo "▸ Delta (records at Namecheap NOT in Cloudflare):"
python3 <<EOF
import json
nc = $NC_JSON
cf = json.loads('''$(echo "$CF_RECORDS" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["result"]))')''')

domain = "$DOMAIN"
def fqdn(n):
    return domain if n in ("@","") else f"{n}.{domain}"

# Build sets keyed by (type, fqdn, content) — content normalized (no trailing dot)
def key(r, name_field, addr_field):
    return (r["type"], fqdn(r[name_field]).lower(), r[addr_field].rstrip(".").lower())

nc_keys = {key(h, "name", "address") for h in nc["hosts"]}
cf_keys = {(r["type"], r["name"].lower(), r["content"].rstrip(".").lower()) for r in cf}

missing = nc_keys - cf_keys
extra = cf_keys - nc_keys

if not missing:
    print("    🟢 all Namecheap records present in Cloudflare")
else:
    for k in sorted(missing):
        print(f"    🔴 MISSING in CF: {k[0]:<5} {k[1]} → {k[2]}")

if extra:
    print()
    print("▸ In Cloudflare but NOT at Namecheap:")
    for k in sorted(extra):
        # ignore CF auto-generated SOA/NS for the apex
        if k[0] in ("SOA","NS") and k[1] == domain.lower():
            continue
        print(f"    🟡 EXTRA in CF: {k[0]:<5} {k[1]} → {k[2]}")
EOF
echo ""
echo "═══════════════════════════════════════════════════════════════"
