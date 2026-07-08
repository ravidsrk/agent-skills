#!/bin/bash
# End-to-end DNS migration: <registrar> → Cloudflare.
# Usage: ./migrate.sh <domain> <step> [--dry-run] [--keep-eforward]
#   steps:  create | import | verify | flip | watch | full
#
# - create : add zone to Cloudflare (uses GLOBAL key)
# - import : copy all records from Namecheap to Cloudflare zone (account token)
#            By default we DO NOT import Namecheap's eforward MX/SPF forwarding
#            records — they stop working the moment you flip NS to Cloudflare.
#            Pass --keep-eforward to import them anyway (useful if you're
#            keeping Namecheap forwarding as a temporary bridge).
# - verify : query Cloudflare's NS directly to confirm zone is correct
# - flip   : update nameservers at Namecheap (--dry-run prints what it would send)
# - watch  : poll public DNS until cutover propagates
# - full   : run create → import → verify, then STOP so you can review before
#            invoking `flip` yourself. Never auto-flips.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
STEP="${2:-full}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain> <step|full> [--dry-run] [--keep-eforward]"
  exit 1
fi

# Trim off <domain> and <step> from $@ before flag parsing
shift $(( $# < 2 ? $# : 2 )) || true

DRY_RUN="false"
KEEP_EFORWARD="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)        DRY_RUN="true" ;;
    --keep-eforward)  KEEP_EFORWARD="true" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

read -r SLD TLD <<< "$(domain_split "$DOMAIN")"
DIR="$(state_dir "$DOMAIN")"

# ---------------------------------------------------------------------------
step_create() {
  echo "-- STEP: create zone $DOMAIN in Cloudflare"
  require_env CLOUDFLARE_API_KEY CLOUDFLARE_GLOBAL_API_KEY CLOUDFLARE_EMAIL

  local existing
  existing=$(cf_zone_id "$DOMAIN")
  if [ -n "$existing" ]; then
    echo "  zone already exists: ${existing:0:8}***"
    cf_api GET "/zones/${existing}" > "${DIR}/cloudflare-zone.json"
    return 0
  fi

  echo "  resolving account ID via global key..."
  local acct_resp acct_id
  acct_resp=$(curl -sS "https://api.cloudflare.com/client/v4/accounts?per_page=1" \
    -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
    -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}")
  cf_assert_success "$acct_resp" "list accounts (global key)"
  acct_id=$(echo "$acct_resp" | python3 -c "
import json, sys
r = json.load(sys.stdin).get('result') or []
if not r:
    sys.exit('ERROR: Cloudflare returned zero accounts')
print(r[0]['id'])
")
  echo "  account: ${acct_id:0:8}***"

  local resp
  resp=$(cf_global POST "/zones" \
    "{\"name\":\"${DOMAIN}\",\"account\":{\"id\":\"${acct_id}\"},\"type\":\"full\"}")
  cf_assert_success "$resp" "create zone"

  echo "$resp" > "${DIR}/cloudflare-zone.json"
  python3 <<EOF
import json
z = json.load(open("${DIR}/cloudflare-zone.json"))['result']
print(f"  (OK) zone created: id={z['id'][:8]}*** status={z['status']}")
print(f"  Cloudflare nameservers:")
for ns in z['name_servers']:
    print(f"    - {ns}")
print(f"  original nameservers (registrar):")
for ns in z['original_name_servers']:
    print(f"    - {ns}")
EOF
}

# ---------------------------------------------------------------------------
step_import() {
  echo "-- STEP: import records from Namecheap into Cloudflare zone $DOMAIN"
  require_env CLOUDFLARE_API_KEY NAMECHEAP_API_KEY NAMECHEAP_API_USER

  local zone_id
  zone_id=$(cf_zone_id "$DOMAIN")
  if [ -z "$zone_id" ]; then
    echo "  ERROR: zone does not exist in Cloudflare. Run: $0 $DOMAIN create" >&2
    exit 1
  fi
  echo "  zone_id: ${zone_id:0:8}***"

  # 1. Get current Namecheap records
  local nc_xml
  nc_xml=$(nc_get_hosts "$SLD" "$TLD")
  echo "$nc_xml" | nc_hosts_to_json > "${DIR}/namecheap-records.json"
  local email_type
  email_type=$(python3 -c "
import json
print(json.load(open('${DIR}/namecheap-records.json'))['email_type'])")

  # 2. Get current CF records (for idempotency: skip ones already there)
  local cf_resp
  cf_resp=$(cf_api GET "/zones/${zone_id}/dns_records?per_page=100")
  cf_assert_success "$cf_resp" "list CF records"
  local cf_existing_keys
  cf_existing_keys=$(echo "$cf_resp" | python3 -c "
import json, sys
d = json.load(sys.stdin)
keys = []
for r in d['result']:
    keys.append(f\"{r['type']}|{r['name'].lower()}|{r['content'].rstrip('.').lower()}\")
print('\n'.join(keys))")

  # 3. Build the records to import
  echo ""
  echo "  records to import:"
  local skipped_unsupported=0
  while IFS= read -r record_json; do
    [ -z "$record_json" ] && continue
    local cf_body
    cf_body=$(echo "$record_json" | nc_to_cf_record "$DOMAIN")

    # Unsupported types (URL/URL301/FRAME) produce a SKIP:<reason> line
    if [[ "$cf_body" == SKIP:* ]]; then
      local reason="${cf_body#SKIP:}"
      local orig_name orig_type orig_addr
      orig_name=$(echo "$record_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
      orig_type=$(echo "$record_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('type',''))")
      orig_addr=$(echo "$record_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('address',''))")
      echo "    [!] SKIP unsupported: ${orig_type} ${orig_name} -> ${orig_addr}"
      echo "        ${reason}"
      skipped_unsupported=$((skipped_unsupported+1))
      continue
    fi

    local k
    k=$(echo "$cf_body" | python3 -c "
import json, sys
r = json.load(sys.stdin)
print(f\"{r['type']}|{r['name'].lower()}|{r['content'].rstrip('.').lower()}\")")

    if echo "$cf_existing_keys" | grep -qx "$k"; then
      echo "    [SKIP already exists]: $(echo "$cf_body" | python3 -c "import json,sys; r=json.load(sys.stdin); print(f'{r[\"type\"]:<5} {r[\"name\"]:<40} -> {r[\"content\"]}')")"
      continue
    fi

    echo "    [ADD]:                  $(echo "$cf_body" | python3 -c "import json,sys; r=json.load(sys.stdin); print(f'{r[\"type\"]:<5} {r[\"name\"]:<40} -> {r[\"content\"]}')")"
    local resp
    resp=$(cf_api POST "/zones/${zone_id}/dns_records" "$cf_body")
    cf_assert_success "$resp" "create record $k"
  done < <(python3 -c "
import json
d = json.load(open('${DIR}/namecheap-records.json'))
for h in d['hosts']:
    print(json.dumps(h))")

  if [ "$skipped_unsupported" -gt 0 ]; then
    echo ""
    echo "  [!] ${skipped_unsupported} unsupported record(s) skipped — configure Cloudflare Redirect Rules manually."
  fi

  # 4. Namecheap email forwarding — DEFAULT is NOT to import.
  #    After NS flips to Cloudflare, Namecheap stops forwarding; the eforwardN
  #    MX targets keep resolving but the mail-relay service refuses the domain.
  #    Importing them silently gives users the illusion email still works.
  if [ "$email_type" = "FWD" ]; then
    echo ""
    if [ "$KEEP_EFORWARD" = "true" ]; then
      echo "  [!] Namecheap EmailType=FWD detected — --keep-eforward set, importing MX+SPF"
      for entry in \
        "10|eforward1.registrar-servers.com" \
        "10|eforward2.registrar-servers.com" \
        "10|eforward3.registrar-servers.com" \
        "15|eforward4.registrar-servers.com" \
        "20|eforward5.registrar-servers.com"; do
        local pref="${entry%%|*}"
        local target="${entry##*|}"
        local k="MX|${DOMAIN}.|${target}"
        if echo "$cf_existing_keys" | grep -qx "$k"; then
          echo "    [SKIP MX exists]: ${pref} ${target}"
          continue
        fi
        local mx_body
        mx_body=$(python3 -c "
import json
print(json.dumps({
  'type':'MX','name':'${DOMAIN}','content':'${target}',
  'priority':${pref},'ttl':300,'proxied':False,
  'comment':'Namecheap email forwarding (--keep-eforward)'
}))")
        echo "    [ADD MX]:         ${pref} ${target}"
        cf_api POST "/zones/${zone_id}/dns_records" "$mx_body" > /dev/null
      done

      local spf="v=spf1 include:spf.efwd.registrar-servers.com ~all"
      local spf_k="TXT|${DOMAIN}.|\"${spf}\""
      if ! echo "$cf_existing_keys" | grep -qx "$spf_k"; then
        local txt_body
        txt_body=$(python3 -c "
import json
print(json.dumps({
  'type':'TXT','name':'${DOMAIN}','content':'\"${spf}\"',
  'ttl':300,'proxied':False,
  'comment':'SPF for Namecheap email forwarding (--keep-eforward)'
}))")
        echo "    [ADD TXT SPF]:    ${spf}"
        cf_api POST "/zones/${zone_id}/dns_records" "$txt_body" > /dev/null
      fi
    else
      cat <<'WARN'

  =====================================================================
  [!] EMAIL FORWARDING WARNING
  Namecheap EmailType=FWD is set on this domain. Those eforwardN MX
  records were NOT imported. Namecheap's forwarding service stops
  relaying mail for your domain the moment you flip NS away — even if
  the MX records still point at eforwardN.registrar-servers.com.

  Choose ONE of:
    1. Set up Cloudflare Email Routing (recommended) before flipping NS.
    2. Point MX at a real mailbox provider (Fastmail, Google, etc.).
    3. Pass --keep-eforward to import the MX+SPF anyway (mail WILL
       break at flip; use only if you plan to change providers within
       hours).
  =====================================================================
WARN
    fi
  fi

  # 5. Save what we imported
  cf_api GET "/zones/${zone_id}/dns_records?per_page=100" > "${DIR}/records-imported.json"
  local final_count
  final_count=$(python3 -c "import json; print(len(json.load(open('${DIR}/records-imported.json'))['result']))")
  echo ""
  echo "  (OK) import complete — Cloudflare zone now has ${final_count} records"
}

# ---------------------------------------------------------------------------
step_verify() {
  echo "-- STEP: verify zone by querying Cloudflare's NS DIRECTLY"
  require_env CLOUDFLARE_API_KEY

  local zone_id
  zone_id=$(cf_zone_id "$DOMAIN")
  [ -z "$zone_id" ] && { echo "  ERROR: zone not found" >&2; exit 1; }

  # Get the assigned NS for this zone
  local ns_list
  ns_list=$(cf_api GET "/zones/${zone_id}" | python3 -c "
import json,sys
print('\n'.join(json.load(sys.stdin)['result']['name_servers']))")
  local primary_ns
  primary_ns=$(echo "$ns_list" | head -n 1)
  echo "  querying ${primary_ns} (first of: $(echo "$ns_list" | tr '\n' ',' | sed 's/,$//'))"
  echo ""

  # Get the records we expect (from CF zone)
  local expected
  expected=$(cf_api GET "/zones/${zone_id}/dns_records?per_page=100")

  local report="${DIR}/verify.log"
  : > "$report"
  local failures=0 checked=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local rtype rname rcontent
    rtype=$(echo "$line" | cut -d'|' -f1)
    rname=$(echo "$line" | cut -d'|' -f2)
    rcontent=$(echo "$line" | cut -d'|' -f3)

    if [ "$rtype" = "NS" ] || [ "$rtype" = "SOA" ]; then continue; fi

    checked=$((checked+1))
    local result
    result=$(dns_direct_query "$primary_ns" "$rname" "$rtype" 2>&1 || echo '{"error":"query failed"}')
    local rtype_pad
    rtype_pad=$(printf '%-5s' "$rtype")

    local match
    match=$(echo "$result" | python3 -c "
import json, sys, ipaddress
expected = sys.argv[1].strip().rstrip('.').lower()
rtype = sys.argv[2].upper()
try:
    d = json.loads(sys.stdin.read())
    answers = d.get('answers', [])
    if not answers:
        print('NO_ANSWER'); sys.exit()
    def norm(v):
        v = v.strip().rstrip('.').lower().strip('\"')
        if rtype == 'AAAA':
            try: v = str(ipaddress.IPv6Address(v))
            except Exception: pass
        if rtype == 'MX':
            parts = v.split(None, 1)
            v = parts[1] if len(parts) == 2 else v
        return v.rstrip('.').lower()
    ne = norm(expected)
    nm = [norm(a['data']) for a in answers]
    print('OK' if any(ne == m or ne in m or m in ne for m in nm) else f'MISMATCH (got: {nm})')
except Exception as e:
    print(f'ERROR: {e}')
" "$rcontent" "$rtype")

    if [ "$match" = "OK" ]; then
      echo "  (OK)         ${rtype_pad} ${rname} -> ${rcontent}" | tee -a "$report"
    elif [ "$match" = "NO_ANSWER" ]; then
      echo "  NO_ANSWER    ${rtype_pad} ${rname}" | tee -a "$report"
      failures=$((failures+1))
    else
      echo "  ${match}     ${rtype_pad} ${rname} (expected ${rcontent})" | tee -a "$report"
      failures=$((failures+1))
    fi
  done < <(echo "$expected" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for r in d['result']:
    print(f\"{r['type']}|{r['name']}|{r['content'].rstrip('.').lower()}\")")

  echo ""
  echo "  checked=$checked  failures=$failures"
  if [ "$failures" -gt 0 ]; then
    echo "  verification failed — DO NOT FLIP NS YET" >&2
    return 1
  fi
  echo "  (OK) zone is correct on Cloudflare's NS — safe to flip"
}

# ---------------------------------------------------------------------------
step_flip() {
  echo "-- STEP: flip nameservers at Namecheap -> Cloudflare"
  require_env CLOUDFLARE_API_KEY NAMECHEAP_API_KEY NAMECHEAP_API_USER

  local zone_id
  zone_id=$(cf_zone_id "$DOMAIN")
  [ -z "$zone_id" ] && { echo "  ERROR: zone not found" >&2; exit 1; }

  local cf_ns
  cf_ns=$(cf_api GET "/zones/${zone_id}" | python3 -c "
import json,sys
print(' '.join(json.load(sys.stdin)['result']['name_servers']))")

  if [ -z "${cf_ns// /}" ]; then
    echo "  ERROR: no Cloudflare nameservers returned — aborting" >&2
    return 1
  fi

  echo "  Namecheap will be updated to:"
  # shellcheck disable=SC2086
  for ns in $cf_ns; do echo "    -> $ns"; done

  if [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo "  DRY-RUN: would call namecheap.domains.dns.setCustom with:"
    echo "    SLD=${SLD} TLD=${TLD}"
    # shellcheck disable=SC2086
    echo "    Nameservers=$(IFS=,; echo $cf_ns)"
    echo "  No changes made."
    return 0
  fi
  echo ""

  local resp
  # shellcheck disable=SC2086
  resp=$(nc_set_nameservers "$SLD" "$TLD" $cf_ns)
  echo "$resp" > "${DIR}/flip.log"

  # Namecheap returns Status="OK" at the outer envelope for API-auth success
  # AND Updated="true" only when the change actually landed. Require both.
  if echo "$resp" | grep -q 'Status="OK"'; then
    if echo "$resp" | grep -q 'Updated="true"'; then
      echo "  (OK) nameservers updated at Namecheap [Updated=true]"
    else
      echo "  Namecheap returned Status=OK but Updated=false — change did not land" >&2
      grep -oE '<Error[^>]*>[^<]+</Error>' "${DIR}/flip.log" | head -5 >&2 || true
      return 1
    fi
  else
    echo "  Namecheap returned an error — see ${DIR}/flip.log" >&2
    grep -oE '<Error[^>]*>[^<]+</Error>' "${DIR}/flip.log" | head -5 >&2 || true
    return 1
  fi
}

# ---------------------------------------------------------------------------
step_watch() {
  echo "-- STEP: watch propagation"
  echo "  polling Cloudflare's 1.1.1.1 + Google's 8.8.8.8 every 30s"
  require_env CLOUDFLARE_API_KEY
  local zone_id
  zone_id=$(cf_zone_id "$DOMAIN")
  local cf_ns_canon
  cf_ns_canon=$(cf_api GET "/zones/${zone_id}" | python3 -c "
import json,sys; print(','.join(sorted(json.load(sys.stdin)['result']['name_servers'])))")
  cf_ns_canon=$(echo "$cf_ns_canon" | tr '[:upper:]' '[:lower:]')

  # Watch up to 30 iterations × 30s = 15 min.
  for i in $(seq 1 30); do
    local got_1111 got_8888
    got_1111=$(curl -sH "accept: application/dns-json" "https://1.1.1.1/dns-query?name=${DOMAIN}&type=NS" \
      | python3 -c "import json,sys; ans=json.load(sys.stdin).get('Answer',[]); print(','.join(sorted(a['data'].rstrip('.').lower() for a in ans)))")
    got_8888=$(curl -sH "accept: application/dns-json" "https://8.8.8.8/resolve?name=${DOMAIN}&type=NS" \
      | python3 -c "import json,sys; ans=json.load(sys.stdin).get('Answer',[]); print(','.join(sorted(a['data'].rstrip('.').lower() for a in ans)))")

    # already-lower from the python normalisation, but be defensive
    got_1111=$(echo "$got_1111" | tr '[:upper:]' '[:lower:]')
    got_8888=$(echo "$got_8888" | tr '[:upper:]' '[:lower:]')

    echo "  [$i/30] 1.1.1.1: ${got_1111:-(none)}"
    echo "         8.8.8.8: ${got_8888:-(none)}"

    if [ "$got_1111" = "$cf_ns_canon" ] && [ "$got_8888" = "$cf_ns_canon" ]; then
      echo "  (OK) propagation complete on both resolvers"
      local cf_status
      cf_status=$(cf_api GET "/zones/${zone_id}" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['status'])")
      echo "  Cloudflare zone status: ${cf_status}"
      return 0
    fi
    sleep 30
  done
  echo "  propagation still incomplete after 15min — keep checking with: $0 $DOMAIN watch"
}

# ---------------------------------------------------------------------------
case "$STEP" in
  create) step_create ;;
  import) step_import ;;
  verify) step_verify ;;
  flip)   step_flip ;;
  watch)  step_watch ;;
  full)
    step_create
    echo ""
    step_import
    echo ""
    step_verify
    echo ""
    echo "============================================================"
    echo "  [!] About to FLIP NAMESERVERS at Namecheap to Cloudflare."
    echo "  This is the only step that affects live traffic."
    echo "  Re-run with: $0 $DOMAIN flip           # (add --dry-run to preview)"
    echo "  Then:        $0 $DOMAIN watch"
    echo "============================================================"
    ;;
  *) echo "Unknown step: $STEP" >&2; exit 1 ;;
esac
