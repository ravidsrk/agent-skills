#!/bin/bash
# Generate a Cloudflare Origin CA certificate (free, 15-year validity).
# Usage: ./origin-ca.sh <domain> [--rsa | --validity-days=5475]
#
# What it does:
#   1. Generates a local ECC P-256 (or RSA-2048) private key
#   2. Builds a CSR with SANs for <domain> and *.<domain>
#   3. Submits to Cloudflare Origin CA — gets back a 15-year cert
#   4. Saves both files in .dns-state/<domain>/origin-ca/
#
# Why use Origin CA over Let's Encrypt:
#   - No 90-day rotation hassle (15 years instead)
#   - Trusted only by Cloudflare's edge — perfect for CF↔origin tunnel
#   - Compatible with SSL mode = "Full (strict)" which we set up
#   - Doesn't require _acme-challenge DNS records anymore
#
# Install on the origin (Fly example):
#   fly certs add example.com -a your-app  # already exists
#   fly secrets set TLS_CERT="$(cat origin-cert.pem)" TLS_KEY="$(cat origin-key.pem)" -a your-app
#   (then configure your app/Caddy/nginx to use those secrets)
#
# Or for nginx:
#   ssl_certificate     /path/to/origin-cert.pem;
#   ssl_certificate_key /path/to/origin-key.pem;

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain> [--rsa] [--validity-days=N]"; exit 1; }
shift || true

KEY_TYPE="ecc"      # ecc (default) or rsa
VALIDITY=5475       # 15 years (max). Other valid values: 7, 30, 90, 365, 730, 1095
HOSTNAMES="\"$DOMAIN\",\"*.$DOMAIN\""

while [ $# -gt 0 ]; do
  case "$1" in
    --rsa)              KEY_TYPE="rsa" ;;
    --validity-days=*)  VALIDITY="${1#*=}" ;;
    --hostnames=*)      HOSTNAMES=$(echo "${1#*=}" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip().split(',')))" | tr -d '[]') ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

REQUIRE_GLOBAL_KEY=1 require_env

DIR="$(state_dir "$DOMAIN")/origin-ca"
mkdir -p "$DIR"
cd "$DIR"

echo "▸ Generating Origin CA certificate for $DOMAIN"
echo "  key type:    $KEY_TYPE"
echo "  validity:    $VALIDITY days (~$((VALIDITY/365)) years)"
echo "  hostnames:   $HOSTNAMES"
echo ""

# 1. Generate private key
if [ ! -f origin-key.pem ]; then
  if [ "$KEY_TYPE" = "rsa" ]; then
    openssl genrsa -out origin-key.pem 2048 2>/dev/null
  else
    openssl ecparam -genkey -name prime256v1 -out origin-key.pem 2>/dev/null
  fi
  chmod 600 origin-key.pem
  echo "  🟢 generated origin-key.pem ($(wc -c < origin-key.pem) bytes, mode 600)"
else
  echo "  🟡 using existing origin-key.pem (delete to regenerate)"
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
echo "  🟢 generated origin.csr"

# 3. Submit to Cloudflare
CSR_JSON=$(python3 -c "import json; print(json.dumps(open('origin.csr').read()))")
REQUEST_TYPE="origin-ecc"
[ "$KEY_TYPE" = "rsa" ] && REQUEST_TYPE="origin-rsa"

# Origin CA endpoint requires global key (or User Service Key — global key works fine)
RESP=$(curl -sS -X POST "https://api.cloudflare.com/client/v4/certificates" \
  -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
  -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
  -H "Content-Type: application/json" \
  --data "{\"hostnames\":[${HOSTNAMES}],\"requested_validity\":${VALIDITY},\"request_type\":\"${REQUEST_TYPE}\",\"csr\":${CSR_JSON}}")

if ! echo "$RESP" | grep -q '"success":true'; then
  echo "  🔴 Origin CA request failed:" >&2
  echo "$RESP" | python3 -m json.tool >&2
  exit 1
fi

# 4. Save the cert + meta
python3 -c "
import json
d = json.loads('''$(echo "$RESP" | python3 -c 'import sys; print(sys.stdin.read())' )''')
r = d['result']
open('origin-cert.pem','w').write(r['certificate'])
meta = {k: v for k, v in r.items() if k != 'certificate'}
open('origin-cert-meta.json','w').write(json.dumps(meta, indent=2))
"

# 5. Verify and report
echo "  🟢 Origin CA certificate signed and saved"
echo ""
openssl x509 -in origin-cert.pem -noout -subject -issuer -dates -ext subjectAltName 2>&1 | sed 's/^/    /'
echo ""
echo "  Files in $DIR:"
ls -la origin-cert.pem origin-key.pem | awk '{print "    " $1 " " $5 "B " $9}'
echo ""
echo "  ⚠️  origin-key.pem is the PRIVATE key — never commit to git, treat as a secret."
echo ""
echo "▸ Install on Fly (example):"
cat <<EOF
    fly secrets set --app your-app \\
      TLS_CERT="\$(cat ${DIR}/origin-cert.pem)" \\
      TLS_KEY="\$(cat ${DIR}/origin-key.pem)"

    # Then configure your app to load TLS_CERT/TLS_KEY at runtime,
    # OR use Fly's built-in TLS termination with a custom cert.
EOF
echo ""
echo "▸ Or directly mount via Fly volumes / Caddy / nginx — see"
echo "  https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/"
