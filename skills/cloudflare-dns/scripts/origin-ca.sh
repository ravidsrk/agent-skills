#!/bin/bash
# Generate a Cloudflare Origin CA certificate (free, 15-year validity).
# Usage: ./origin-ca.sh <domain> [--rsa | --validity-days=5475 | --hostnames=host1,host2,...]
#
# Auth:
#   Prefers CLOUDFLARE_API_KEY (account token with Origin CA:Edit scope).
#   Falls back to CLOUDFLARE_GLOBAL_API_KEY + CLOUDFLARE_EMAIL if the account
#   token can't hit Origin CA — either works.
#
# What it does:
#   1. Generates a local ECC P-256 (or RSA-2048) private key
#   2. Builds a CSR with SANs for <domain> and *.<domain>
#   3. Submits to Cloudflare Origin CA — gets back a 15-year cert
#   4. Saves both files in .dns-state/<domain>/origin-ca/

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain> [--rsa] [--validity-days=N] [--hostnames=list]"; exit 1; }
shift || true

KEY_TYPE="ecc"      # ecc (default) or rsa
VALIDITY=5475       # 15 years (max). Other valid values: 7, 30, 90, 365, 730, 1095
HOSTNAMES_CSV=""    # will default to "<domain>,*.<domain>"

while [ $# -gt 0 ]; do
  case "$1" in
    --rsa)              KEY_TYPE="rsa" ;;
    --validity-days=*)  VALIDITY="${1#*=}" ;;
    --hostnames=*)      HOSTNAMES_CSV="${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

require_env CLOUDFLARE_API_KEY

DIR="$(state_dir "$DOMAIN")/origin-ca"
mkdir -p "$DIR"
cd "$DIR"

# Build HOSTNAMES JSON array safely via python (no shell-brackets round-tripping).
HOSTNAMES_JSON=$(DOM="$DOMAIN" HOSTS_CSV="$HOSTNAMES_CSV" python3 -c "
import json, os
csv = os.environ['HOSTS_CSV'].strip()
if csv:
    hosts = [h.strip() for h in csv.split(',') if h.strip()]
else:
    d = os.environ['DOM']
    hosts = [d, f'*.{d}']
print(json.dumps(hosts))")

echo "-- Generating Origin CA certificate for $DOMAIN"
echo "  key type:    $KEY_TYPE"
echo "  validity:    $VALIDITY days (~$((VALIDITY/365)) years)"
echo "  hostnames:   $HOSTNAMES_JSON"
echo ""

# 1. Generate private key
if [ ! -f origin-key.pem ]; then
  if [ "$KEY_TYPE" = "rsa" ]; then
    openssl genrsa -out origin-key.pem 2048 2>/dev/null
  else
    openssl ecparam -genkey -name prime256v1 -out origin-key.pem 2>/dev/null
  fi
  chmod 600 origin-key.pem
  echo "  (OK) generated origin-key.pem ($(wc -c < origin-key.pem) bytes, mode 600)"
else
  echo "  using existing origin-key.pem (delete to regenerate)"
fi

# 2. Build CSR
cat > csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[ dn ]
CN = $DOMAIN
O = YourOrg
C = US

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
EOF

openssl req -new -key origin-key.pem -out origin.csr -config csr.conf 2>/dev/null
echo "  (OK) generated origin.csr"

# 3. Build request body (write to disk — no bash-string round-tripping)
REQUEST_TYPE="origin-ecc"
[ "$KEY_TYPE" = "rsa" ] && REQUEST_TYPE="origin-rsa"

HOSTNAMES_JSON="$HOSTNAMES_JSON" VALIDITY="$VALIDITY" REQ_TYPE="$REQUEST_TYPE" python3 - <<'PYEOF' > request.json
import json, os
body = {
    'hostnames': json.loads(os.environ['HOSTNAMES_JSON']),
    'requested_validity': int(os.environ['VALIDITY']),
    'request_type': os.environ['REQ_TYPE'],
    'csr': open('origin.csr').read(),
}
print(json.dumps(body))
PYEOF

# 4. Submit — try account token first, fall back to global key if available.
CF_ORIGIN_URL="https://api.cloudflare.com/client/v4/certificates"
RESP=$(curl -sS -X POST "$CF_ORIGIN_URL" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
  -H "Content-Type: application/json" \
  --data @request.json)

if ! echo "$RESP" | grep -q '"success":true'; then
  if [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
    echo "  account-token Origin CA call failed; retrying with CLOUDFLARE_GLOBAL_API_KEY" >&2
    RESP=$(curl -sS -X POST "$CF_ORIGIN_URL" \
      -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
      -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
      -H "Content-Type: application/json" \
      --data @request.json)
  fi
fi

if ! echo "$RESP" | grep -q '"success":true'; then
  echo "  Origin CA request failed:" >&2
  echo "$RESP" | python3 -m json.tool >&2
  exit 1
fi

# 5. Save the cert + meta (write response to disk, read from disk — no round-trip)
echo "$RESP" > response.json
python3 - <<'PYEOF'
import json
d = json.load(open('response.json'))
r = d['result']
open('origin-cert.pem','w').write(r['certificate'])
meta = {k: v for k, v in r.items() if k != 'certificate'}
open('origin-cert-meta.json','w').write(json.dumps(meta, indent=2))
PYEOF

# Clean scratch
rm -f response.json request.json csr.conf origin.csr

# 6. Verify and report
echo "  (OK) Origin CA certificate signed and saved"
echo ""
openssl x509 -in origin-cert.pem -noout -subject -issuer -dates -ext subjectAltName 2>&1 | sed 's/^/    /'
echo ""
echo "  Files in $DIR:"
ls -la origin-cert.pem origin-key.pem | awk '{print "    " $1 " " $5 "B " $9}'
echo ""
echo "  [!] origin-key.pem is the PRIVATE key — never commit to git, treat as a secret."
echo ""
echo "-- Install on Fly (example):"
cat <<EOF
    fly secrets set --app your-app \\
      TLS_CERT="\$(cat ${DIR}/origin-cert.pem)" \\
      TLS_KEY="\$(cat ${DIR}/origin-key.pem)"
EOF
echo ""
echo "-- Or directly mount via Fly volumes / Caddy / nginx — see"
echo "  https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/"
