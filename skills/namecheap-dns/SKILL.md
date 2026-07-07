---
name: namecheap-dns
description: >-
  Manage DNS records at Namecheap programmatically — list, add, update, or delete
  A / AAAA / CNAME / TXT / MX records via the Namecheap XML API, safely wrapping
  the destructive wholesale-replace setHosts endpoint.
  Use when the user wants to set up subdomains, link a custom domain to a Fly app /
  Vercel / S3 / etc., add MX records, rotate SPF/DKIM/DMARC, or flip nameservers
  when migrating away from Namecheap.
license: MIT
compatibility: Requires python3 (stdlib only), bash, curl. Env: NAMECHEAP_API_KEY, NAMECHEAP_API_USER. Outbound IP must be whitelisted at Namecheap.
metadata:
  version: "1.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Namecheap DNS

Manage DNS records at Namecheap via the XML API. The API has two
quirks that bite first-time users:

1. **IP allowlist required** — every request must come from an IP
   pre-whitelisted at Namecheap → Profile → Tools → Namecheap API
   Access → Whitelisted IPs. **Sandbox IPs change between
   sessions; always confirm with `curl -s https://api.ipify.org`
   first.** If you get error `1011150 Invalid request IP: <ip>`, ask
   the user to add that IP to the whitelist.
2. **Updates are wholesale** — there is no "add one record" endpoint.
   `setHosts` REPLACES every record on the domain. You must `getHosts`
   first, then resend ALL existing records plus your new one.

`scripts/setHosts.py` wraps both quirks safely — prefer it over hand-rolled
curl for anything more than a one-off inline test.

## Required environment

| Env var | What it is |
|---|---|
| `NAMECHEAP_API_KEY` | Namecheap API Key (Profile → Tools → API Access) |
| `NAMECHEAP_API_USER` | Namecheap account username. Also used as `ApiUser` and `UserName` on every call. |
| `CLIENT_IP` (optional) | Force a specific whitelisted IP; otherwise derived from `api.ipify.org`. |

## Endpoint

Production: `https://api.namecheap.com/xml.response`
Sandbox: `https://api.sandbox.namecheap.com/xml.response` (separate
account; usually you want production)

## List records

```bash
MY_IP=$(curl -s https://api.ipify.org)
curl -s -G "https://api.namecheap.com/xml.response" \
  --data-urlencode "ApiUser=$NAMECHEAP_API_USER" \
  --data-urlencode "ApiKey=$NAMECHEAP_API_KEY" \
  --data-urlencode "UserName=$NAMECHEAP_API_USER" \
  --data-urlencode "ClientIp=$MY_IP" \
  --data-urlencode "Command=namecheap.domains.dns.getHosts" \
  --data-urlencode "SLD=your-app" \
  --data-urlencode "TLD=ai"
```

Parse the XML response — each record looks like:

```xml
<host HostId="498699225" Name="www" Type="CNAME"
      Address="your-app.fly.dev." MXPref="10" TTL="300"
      IsActive="true" />
```

Prefer `xml.etree.ElementTree` over regex when parsing — URL-redirect
records (`Type=URL` / `URL301` / `FRAME`) have `Address` values containing
`/`, which breaks naïve regex parsers and silently drops those records.

## Add or update records (setHosts replaces all)

**You MUST include every existing record you want to keep, plus the
new one.** Forgetting any record will silently delete it.

**Indices must be contiguous starting at 1** — Namecheap drops records
past the first gap. So use `HostName1..HostNameN` with no skipped
numbers. The example below uses 1, 2, 3 (not 1, 2, 5).

```bash
MY_IP=$(curl -s https://api.ipify.org)

curl -s -G "https://api.namecheap.com/xml.response" \
  --data-urlencode "ApiUser=$NAMECHEAP_API_USER" \
  --data-urlencode "ApiKey=$NAMECHEAP_API_KEY" \
  --data-urlencode "UserName=$NAMECHEAP_API_USER" \
  --data-urlencode "ClientIp=$MY_IP" \
  --data-urlencode "Command=namecheap.domains.dns.setHosts" \
  --data-urlencode "SLD=your-app" \
  --data-urlencode "TLD=ai" \
  --data-urlencode "EmailType=FWD" \
  \
  `# existing record 1 (apex A)` \
  --data-urlencode "HostName1=@" \
  --data-urlencode "RecordType1=A" \
  --data-urlencode "Address1=66.241.124.148" \
  --data-urlencode "TTL1=300" \
  \
  `# existing record 2 (apex AAAA)` \
  --data-urlencode "HostName2=@" \
  --data-urlencode "RecordType2=AAAA" \
  --data-urlencode "Address2=2a09:8280:1::e7:30bb:1" \
  --data-urlencode "TTL2=300" \
  \
  `# NEW record 3: docs.your-app.ai → Fly` \
  --data-urlencode "HostName3=docs" \
  --data-urlencode "RecordType3=CNAME" \
  --data-urlencode "Address3=131zmog.your-docs-app.fly.dev." \
  --data-urlencode "TTL3=300"
```

**Success response** contains `Status="OK"` and `IsSuccess="true"`.

Both must be present. `Status="OK"` alone only confirms the auth envelope
succeeded; `IsSuccess="true"` on `DomainDNSSetHostsResult` confirms the
change actually landed.

## Safer alternative: `scripts/setHosts.py`

For anything more than a trivial single-record add, use the helper:

```bash
# Add one record (getHosts → merge → setHosts, contiguous indexing enforced)
NAMECHEAP_API_KEY=... NAMECHEAP_API_USER=... \
python3 scripts/setHosts.py --sld=your-app --tld=ai \
  --add='name=docs&type=CNAME&address=131zmog.your-docs-app.fly.dev.&ttl=300'

# Preview only — don't actually POST setHosts
python3 scripts/setHosts.py --sld=your-app --tld=ai \
  --add='name=api&type=CNAME&address=api.your-app.fly.dev.&ttl=300' \
  --dry-run

# Remove a record (matches on name + type)
python3 scripts/setHosts.py --sld=your-app --tld=ai \
  --remove='name=old&type=CNAME'

# Bulk add from a JSON file
cat > /tmp/records.json <<'EOF'
[
  {"name":"send",             "type":"MX",   "address":"feedback-smtp.us-east-1.amazonses.com.", "mxpref":"10", "ttl":"300"},
  {"name":"send",             "type":"TXT",  "address":"v=spf1 include:amazonses.com ~all",       "ttl":"300"},
  {"name":"resend._domainkey","type":"TXT",  "address":"p=MIGf...long-key...",                    "ttl":"300"}
]
EOF
python3 scripts/setHosts.py --sld=your-app --tld=ai \
  --add-json=/tmp/records.json --email-type=MX
```

The script:

- Fetches all existing records with `getHosts` first
- **Refuses to proceed if `getHosts` returned zero records** or an error
  (a zero-record `setHosts` would wipe the zone on a silent read failure).
  Pass `--force-empty` to override if you truly want to remove every record.
- Merges adds / removes / updates on top of the current record set
- Emits **strictly contiguous 1..N HostName indices**
- Verifies both `Status="OK"` (envelope) and `IsSuccess="true"`
  (`DomainDNSSetHostsResult`) before reporting success

## Standard linking pattern: subdomain → Fly app

```bash
# 1. On Fly: create cert (issues challenge + provisions LB hostname)
fly certs add subdomain.example.com -a my-app

# 2. Get the recommended CNAME target from Fly
fly certs setup subdomain.example.com -a my-app
# → CNAME subdomain.example.com → <hash>.my-app.fly.dev

# 3. Add CNAME at Namecheap
python3 scripts/setHosts.py --sld=example --tld=com \
  --add='name=subdomain&type=CNAME&address=<hash>.my-app.fly.dev.&ttl=300'

# 4. Wait for DNS propagation (60-120s usually)
# Sandbox local DNS is slow; verify via Cloudflare DoH:
curl -s "https://1.1.1.1/dns-query?name=subdomain.example.com&type=CNAME" \
  -H "accept: application/dns-json"

# 5. Verify cert issued
fly certs check subdomain.example.com -a my-app

# 6. Test:
APP_IP=$(curl -s -G "https://1.1.1.1/dns-query?name=my-app.fly.dev&type=A" \
  -H "accept: application/dns-json" | python3 -c "import sys,json; print(json.load(sys.stdin)['Answer'][0]['data'])")
curl -sI --resolve subdomain.example.com:443:$APP_IP \
  https://subdomain.example.com/
```

## Common errors

| Error code | Meaning | Fix |
|---|---|---|
| `1011150` Invalid request IP | Sandbox IP not whitelisted | Get IP via `curl https://api.ipify.org`, ask user to whitelist at Namecheap → Profile → Tools → API |
| `1011102` API Key invalid / API access not enabled | Wrong key, or production/sandbox endpoint mismatch | Check `NAMECHEAP_API_KEY` env var, use `api.namecheap.com` (NOT sandbox) |
| Records silently deleted | Forgot to resend in setHosts, or used non-contiguous indices | Always `getHosts` first; build full record list; keep indices contiguous 1..N. Use `scripts/setHosts.py`. |
| MX records on subdomain silently dropped | `EmailType=FWD` blocks subdomain MX | Use `EmailType=MX` and resend all apex MX records explicitly (eforward1-5) |
| Long DKIM TXT record dropped | Sometimes works on retry | Resend the same setHosts call once or twice — Namecheap occasionally rejects long TXT silently and accepts it on retry |

## Resend domain setup pattern

Resend gives you 3 records to add:
- `resend._domainkey` TXT (DKIM)
- `send` MX → feedback-smtp.us-east-1.amazonses.com
- `send` TXT (SPF)

**Critical**: must use `EmailType=MX`, not `FWD`. If domain currently uses
Namecheap email forwarding, include eforward1-5 MX records explicitly:

```
HostName=@  Type=MX  Address=eforward1.registrar-servers.com.  MXPref=10
HostName=@  Type=MX  Address=eforward2.registrar-servers.com.  MXPref=10
HostName=@  Type=MX  Address=eforward3.registrar-servers.com.  MXPref=10
HostName=@  Type=MX  Address=eforward4.registrar-servers.com.  MXPref=15
HostName=@  Type=MX  Address=eforward5.registrar-servers.com.  MXPref=20
HostName=@  Type=TXT Address="v=spf1 include:spf.efwd.registrar-servers.com ~all"
```

## Cross-skill: migrating away from Namecheap

If the user is moving DNS **from** Namecheap **to** Cloudflare, hand
off to [`cloudflare-dns`](../cloudflare-dns/) for the zone-create /
record-import / verify / NS-flip / rollback pipeline. That skill imports
this skill's helpers for the registrar-side call.

## File: scripts/setHosts.py

The safe wholesale-replace wrapper described above. Reads
`NAMECHEAP_API_KEY`, `NAMECHEAP_API_USER`, and optionally `CLIENT_IP`
from the environment; supports `--dry-run`, `--add`, `--add-json`,
`--remove`, `--email-type`, and `--force-empty`. Refuses to send an
empty setHosts unless `--force-empty` is set.
