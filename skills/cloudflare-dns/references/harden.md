## File: scripts/harden.sh

Production-grade hardening for any zone in Cloudflare. Idempotent.

```bash
scripts/harden.sh <domain>                                    # full Tier 1+2+3 with proxy ON
scripts/harden.sh <domain> --enable-proxy=false               # Tier 1+3 only
scripts/harden.sh <domain> --rate-limit-path=/admin/*         # custom rate-limit path
scripts/harden.sh <domain> --rate-limit-rpm=600               # custom limit
scripts/harden.sh <domain> --no-dnssec                        # skip DNSSEC
scripts/harden.sh <domain> --proxy-records=@,www              # only proxy specific records
```

### Tier 1 — SSL/TLS (always applied, no proxy needed)

| Setting | Value |
|---|---|
| SSL | `Full (strict)` — origin cert must be valid |
| Always Use HTTPS | ON |
| Auto HTTPS Rewrites | ON (fixes mixed content) |
| Min TLS Version | 1.2 |
| TLS 1.3 | ON |
| Opportunistic Encryption | ON |
| 0-RTT | ON |
| HTTP/3 (QUIC) | ON |
| WebSockets | ON (essential for SSE / live apps) |
| IPv6 | ON |
| Email Address Obfuscation | ON |
| Browser Integrity Check | ON |
| Server-Side Excludes | ON |
| HSTS | `max-age=31536000; includeSubDomains; preload; nosniff` |

### Tier 2 — WAF + Bot + Rate Limit (proxy must be ON)

| Setting | Value |
|---|---|
| Proxy on @, www, api, docs (configurable) | ON |
| `_acme-challenge.*` records | KEPT DNS-only (Fly cert renewal) |
| WAF Managed Free Ruleset | Auto-deployed by Cloudflare for free zones |
| Bot Fight Mode + JS Detection | ON (free tier) |
| Security Level | medium |
| Challenge TTL | 30 min |
| Privacy Pass | ON |
| Rate Limit | 1 rule (free tier max), default `50 req/10s/IP` on `/api/*` |

🔴 **Free tier rate-limit constraints (verified 2026-05-02):**

- `period` must be exactly **10** seconds (60 returns "not entitled to period 60")
- `mitigation_timeout` must be exactly **10** seconds
- `matches` regex operator NOT allowed (paid plan required); use `starts_with(...)` or `eq`
- Maximum **1 ratelimit ruleset per zone** on free; the script detects existing ones and skips re-creation
- Approximate "rpm" target: `requests_per_period = max(1, rpm / 6)`

### Tier 3 — DNS-level (zone-wide)

| Record | Value |
|---|---|
| CAA `issue` | `letsencrypt.org` |
| CAA `issue` | `pki.goog` |
| CAA `issue` | `digicert.com` (only if proxy ON, since CF Universal SSL uses DigiCert) |
| CAA `issuewild` | `;` (disallow wildcards unless explicitly added) |
| CAA `iodef` | `mailto:postmaster@<domain>` (incident reports) |
| TXT `_dmarc` | `v=DMARC1; p=none; rua=mailto:postmaster@<domain>; ...` (monitor mode — switch to `p=quarantine` then `p=reject` after 2-4 weeks of clean reports) |
| DNSSEC | Enabled at Cloudflare; **DS record needs manual paste at Namecheap** (their public API doesn't support DS submission) |

### DNSSEC: the manual step

Cloudflare signs the zone immediately, but the parent zone (`.ai`, `.com`, etc.) needs the **DS record** at the registrar to complete the chain of trust. Namecheap's public API doesn't expose DNSSEC endpoints (we tested every undocumented `domains.dnssec.*` command — `add` exists but rejects all parameter shapes from the public API).

After running `harden.sh`, run:

```bash
scripts/dnssec-instructions.sh <domain>
```

This prints the exact values to paste at Namecheap → Domain List → Manage → Advanced DNS → DNSSEC.

Verify after ~60 min with:

```bash
curl -sH 'accept: application/dns-json' \
  'https://1.1.1.1/dns-query?name=<domain>&type=DS' | python3 -m json.tool
```

And the chain at <https://dnsviz.net/d/<domain>/dnssec/>.

### ⚠️ Namecheap DNSSEC submission MUST be done in the UI, not via API

**Don't waste cycles trying to automate this.** Namecheap exposes
`namecheap.domains.dnssec.getList`, `.add`, `.remove` endpoints, but the
`add` parameter shape is undocumented and every reasonable guess returns
`Error 2016166: No records, specify dnssec records.` — including:

- `KeyTag=…&Algorithm=…&DigestType=…&Digest=…` (suffixed and unsuffixed)
- `KeyTag1=…&Algorithm1=…&DigestType1=…&Digest1=…` (1-indexed)
- `DnsSecData=…` / `DnsSecData1=…` / `DnsSecKeys=…` / `DSData=…`
- `DnsSecKeys[0].KeyTag=…` (dotted/bracketed)
- `Records.KeyTag=…` (named subobject)
- `Flags=257&Algorithm=…&PublicKey=…` (DNSKEY shape instead of DS shape)

Both GET and POST. None work. The API command is reseller-only or
internal-only — no public SDK or open-source caller succeeds either.

The known-working flow is the UI: Domain List → Manage → Advanced DNS →
DNSSEC toggle ON → Add new record (KeyTag, Algorithm 13, DigestType 2,
Digest hex). After ~60 min the chain of trust is live.

If you find a working API parameter shape, **update this skill** so the
next migration can automate it.

### Why proxy is OFF on `_acme-challenge.*`

Fly.io renews TLS certificates by responding to ACME challenges via the
`_acme-challenge.<host>` CNAME, which delegates to a `flydns.net` zone Fly
controls. If those records are proxied (orange cloud), Cloudflare intercepts
the response and Fly's renewal fails silently 30 days later when the cert
expires. **Always keep `_acme-challenge.*` records grey-cloud.**

The harden script's `cf_set_proxy` helper only flips A/AAAA/CNAME records
in the configured PROXY_RECORDS list — `_acme-challenge.*` are excluded.

### Why some records (apex `@`) showed Fly server header after proxy flip

The proxy flag was set immediately, but resolvers cached the old grey-cloud
A/AAAA addresses (the Fly anycast IPs). Once those expire (~5 min), CF's
proxy IPs take over and `Server: cloudflare` shows up. This is expected.

### File: scripts/dnssec-instructions.sh

Reads the saved DNSSEC details from `.dns-state/<domain>/dnssec.json` and
prints copy-pasteable instructions for the Namecheap dashboard step.
