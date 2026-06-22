---
name: cloudflare-dns
description: Migrate DNS hosting from Namecheap (or any registrar) to Cloudflare and manage records via API — handles zone creation, bulk record import, nameserver flip at the registrar, propagation watch, and rollback. Use when the user wants to "move DNS to Cloudflare", "add a domain to Cloudflare", "manage Cloudflare DNS records", or "automate DNS setup for multiple sites".
---

# Cloudflare DNS Migration & Management

End-to-end automation for moving domains from any DNS host to Cloudflare,
plus ongoing record management. Designed to be reusable across many domains.

## Required environment

Cloudflare auth needs **two** credentials:

| Var | What it is | When used |
|---|---|---|
| `CLOUDFLARE_API_KEY` | Account-scoped API Token (`cfat_*`) | All ongoing DNS operations: list/add/edit/delete records, zone settings, listing zones. **Use this by default.** |
| `CLOUDFLARE_GLOBAL_API_KEY` + `CLOUDFLARE_EMAIL` | Global API Key + email | **Only** for `POST /zones` (creating new zones in the account). Cloudflare's API requires User-level auth for zone creation; account tokens cannot do this. |

🔴 **Security note.** `CLOUDFLARE_GLOBAL_API_KEY` grants full account access
(billing, members, everything). Treat it carefully:
- Use Bearer auth (`Authorization: Bearer ...`) for `CLOUDFLARE_API_KEY`
- Use header-pair auth (`X-Auth-Key:` + `X-Auth-Email:`) for the global key
- **Never write either to disk, configs, URLs, or git**
- Always pass via env var; never log values

For the registrar side (Namecheap), see the `namecheap-dns` skill —
it shares its IP-allowlist + setHosts conventions with this one.

## The hard rule: zone creation needs Global Key

Account API Tokens (the safer, narrower kind) **cannot create zones**.
Cloudflare's `POST /zones` endpoint always rejects them with:

```
Requires permission "com.cloudflare.api.account.zone.create"
```

This is a Cloudflare API limitation, not a missing permission.
Solution: use the Global API Key for the single zone-create call,
then switch back to the account token for everything else.

The migration scripts handle this split automatically.

## Endpoints reference

| Operation | Method | URL | Auth |
|---|---|---|---|
| Verify token | GET | `/user/tokens/verify` (Bearer) or `/accounts/{id}/tokens/verify` | account token |
| List accounts | GET | `/accounts` | global key |
| List zones | GET | `/zones?name=domain.com` | account token |
| Create zone | POST | `/zones` body `{name, account:{id}, type:"full"}` | **global key only** |
| Delete zone | DELETE | `/zones/{zone_id}` | account token |
| List records | GET | `/zones/{zone_id}/dns_records?per_page=100` | account token |
| Create record | POST | `/zones/{zone_id}/dns_records` | account token |
| Update record | PUT | `/zones/{zone_id}/dns_records/{id}` | account token |
| Delete record | DELETE | `/zones/{zone_id}/dns_records/{id}` | account token |

## Record body shape

```json
{
  "type": "A | AAAA | CNAME | MX | TXT | CAA | SRV | NS",
  "name": "subdomain.example.com",   // FQDN, NOT just "subdomain"
  "content": "1.2.3.4",              // for MX/SRV use specific shapes
  "ttl": 300,                        // 1 = "auto" (300s)
  "proxied": false,                   // grey cloud (DNS only) by default
  "priority": 10,                    // MX records only
  "comment": "..."                   // optional, helpful for audit
}
```

Cloudflare auto-strips the trailing dot on CNAME/MX targets, but be
consistent — pass `your-app.fly.dev.` (with dot) the same way
the registrar stored it.

## Proxy default: OFF (grey cloud)

Set `proxied: false` for everything by default. Reasons:
- WebSockets / SSE often break with default proxy settings
- Fly.io, Vercel, Netlify already terminate TLS — proxying adds
  cert-renewal complications (`_acme-challenge` flow)
- Easier rollback if something is wrong

Enable per-record manually after migration is verified (`/zones/{id}/dns_records/{id}` PATCH `{proxied: true}`).

## Workflow: full migration (Namecheap → Cloudflare)

```
1. Audit current DNS at Namecheap        → scripts/audit.sh <domain>
2. Create zone in Cloudflare              → scripts/migrate.sh <domain> step:create
3. Import all records to Cloudflare       → scripts/migrate.sh <domain> step:import
4. Verify resolution via DoH against
   Cloudflare's NS (BEFORE flipping)      → scripts/migrate.sh <domain> step:verify
5. Flip nameservers at Namecheap          → scripts/migrate.sh <domain> step:flip
6. Watch propagation                      → scripts/migrate.sh <domain> step:watch
```

Pause for confirmation between steps 3 and 5 — the flip is the only
step that affects live traffic.

## Verifying against Cloudflare's NS BEFORE flipping

Cloudflare's nameservers serve the new zone immediately, even though
public DNS still points to Namecheap. Query CF's NS directly to
confirm records are correct:

```bash
# DoH query AGAINST Cloudflare's authoritative NS:
NS=emerson.ns.cloudflare.com  # one of the assigned NS for this zone
NS_IP=$(curl -s "https://1.1.1.1/dns-query?name=$NS&type=A" \
  -H "accept: application/dns-json" | python3 -c "import json,sys; print(json.load(sys.stdin)['Answer'][0]['data'])")

# Direct UDP DNS via dig — but sandbox lacks dig. Use a public DoT/DoH proxy
# OR run kdig if available, OR use python:
python3 -c "
import socket, struct
# (truncated — see scripts/dns-query.py for full impl)
"
```

In practice the `migrate.sh verify` step uses a Python helper that
sends a UDP DNS query directly to the Cloudflare NS IP and parses
the response, so we know the zone is right BEFORE switching.

## Per-domain state

Each migration writes state to `.dns-state/<domain>/`:

```
.dns-state/example.com/
├── audit-pre.json           # records before migration
├── cloudflare-zone.json     # zone metadata + NS
├── records-imported.json    # what was sent to Cloudflare
├── verify.log               # NS-direct query results
├── flip.log                 # registrar response when flipping NS
├── post-cutover.json        # records after migration
└── report.md                # human-readable summary
```

This lets us re-run any step idempotently and roll back precisely.

## Rollback

```bash
scripts/rollback.sh <domain>
```

Sets nameservers back to the pre-migration values (saved in
`audit-pre.json`). The Cloudflare zone is left intact — re-running
`migrate.sh ... step:flip` will redo the cutover without re-importing.

## Common gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `POST /zones` returns code 0 "Requires permission ..." | Used account token instead of global key | Use `CLOUDFLARE_GLOBAL_API_KEY` + `CLOUDFLARE_EMAIL` headers |
| `_acme-challenge` records dropped after migration | Forgot to import them | Always include `_acme-challenge*` CNAMEs — Fly/Vercel/etc need them for cert renewal |
| Email stops working after cutover | Namecheap `EmailType=FWD` auto-injected MX/SPF that aren't stored as host records | Before migration, manually add the eforward MX (10/10/10/15/20 priority) + SPF TXT to Cloudflare |
| Cert renewal fails 30 days post-migration | Same as above (`_acme-challenge` issue) | Verify all `_acme-challenge.*` records are in Cloudflare via `audit.sh` |
| `proxied: true` breaks the site | Cloudflare SSL mode default is "Flexible" | Set zone SSL to "Full (strict)" before enabling proxy, or leave proxy off |
| Namecheap setHosts deletes records | Wholesale replace — must include all records | Use the namecheap-dns skill's `setHosts` pattern |
| Sandbox IP not whitelisted at Namecheap | IP rotates between sandbox sessions | `curl https://api.ipify.org`; ask user to whitelist |
| `harden.sh` reports 4 CAAs added but only 1 (the last) actually persists | `cf_upsert_record` matched on `(type, name)` only. CAA records share that key but differ by `(tag, value)`, so each new CAA UPDATED the previous one instead of inserting alongside. Same bug existed for MX (5 eforward MXes on apex collapse to 1) and TXT (multiple SPF/DKIM/verification TXTs on same name collapse). | Fixed in `lib.sh:cf_upsert_record` — now matches `(type, name, tag, value)` for CAA, `(type, name, content)` for MX/TXT. **Always verify post-hardening:** `cf_api GET "/zones/$ZID/dns_records?type=CAA"` should return 4 records (`issue letsencrypt.org`, `issue pki.goog`, `issuewild ;`, `iodef mailto:…`). |
| Public resolvers (1.1.1.1, 8.8.8.8) keep returning Namecheap NS for 30+ min after the flip — even though the parent TLD is delegating to Cloudflare | "Lame delegation" during a registrar transition: Namecheap's `dns1/dns2.registrar-servers.com` keep claiming `aa=1` (authoritative) and serve in-zone NS records with their own 30min TTL. When a resolver queries Namecheap directly (instead of re-asking the parent), it caches the stale answer until the in-zone TTL expires. | This is expected and harmless — the parent .ai/.com TLD is the source of truth. **Verify the parent directly** using `dns-direct-query.py v0n0.nic.ai example.com NS` (or the equivalent TLD NS for other zones). If the parent says Cloudflare and the CF zone status is `active`, you're done. Public resolvers will catch up within 30-60 min. The site works either way because both NS sets resolve to the same origin records. |

## File: scripts/migrate.sh

The main migration driver. Takes a domain + step, runs that step,
saves state to `.dns-state/<domain>/`. Designed for re-runs.

```bash
scripts/migrate.sh example.com full       # all steps with prompts
scripts/migrate.sh example.com create     # create zone only
scripts/migrate.sh example.com import     # import records only
scripts/migrate.sh example.com verify     # query CF's NS to confirm
scripts/migrate.sh example.com flip       # update NS at Namecheap
scripts/migrate.sh example.com watch      # poll propagation
```

## File: scripts/audit.sh

Read-only state check — current registrar, current NS, current records,
whether zone exists in Cloudflare yet, what's missing. Safe to run anytime.

```bash
scripts/audit.sh example.com
```

## File: scripts/rollback.sh

Sets nameservers at Namecheap back to `dns1/2.registrar-servers.com`
(or the original NS saved in `audit-pre.json`).

```bash
scripts/rollback.sh example.com
```

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

## File: scripts/origin-ca.sh

Generate a Cloudflare Origin CA certificate (15-year validity, free, ECC P-256
or RSA-2048). Writes the cert + private key to `.dns-state/<domain>/origin-ca/`.

```bash
scripts/origin-ca.sh example.com                       # ECC, 15-year, default
scripts/origin-ca.sh example.com --rsa                  # RSA-2048 instead of ECC
scripts/origin-ca.sh example.com --validity-days=365    # shorter cert
scripts/origin-ca.sh other.com --hostnames=other.com,*.other.com,api.other.com
```

Why use Origin CA over Let's Encrypt:

- 🟢 **15 years** vs 90 days — no renewal automation needed
- 🟢 Trusted by Cloudflare's edge — perfect for the CF↔origin tunnel
- 🟢 Compatible with `SSL: Full (strict)` mode (which we set in harden.sh)
- 🟢 Eliminates the need for `_acme-challenge.*` DNS records
- 🟡 NOT publicly trusted — only valid behind Cloudflare's proxy. If you
  also need browsers to trust the origin directly (e.g. for direct API
  access bypassing CF), keep Let's Encrypt as well.

🔴 **The private key (`origin-key.pem`) must NEVER be committed to git or
written to public configs.** Treat it as a secret. Mode 600 is set automatically.

Install on Fly:

```bash
fly secrets set --app your-app \
  TLS_CERT="$(cat .dns-state/example.com/origin-ca/origin-cert.pem)" \
  TLS_KEY="$(cat  .dns-state/example.com/origin-ca/origin-key.pem)"
```

Then configure your app to load `TLS_CERT` / `TLS_KEY` from env at startup.

## File: scripts/dns-export.sh

Export a Cloudflare zone as DNS-as-code (YAML, JSON, BIND zonefile, or Terraform).

```bash
scripts/dns-export.sh example.com                            # YAML (default)
scripts/dns-export.sh example.com --format=json              # raw JSON
scripts/dns-export.sh example.com --format=zonefile          # BIND zonefile
scripts/dns-export.sh example.com --format=terraform         # Terraform .tf
scripts/dns-export.sh example.com --output=./your-app.yaml
```

Useful for:

- 🟢 **Backup** before risky DNS changes
- 🟢 **Source-controlling DNS** so changes go through PR review
- 🟢 **Migration** to a different DNS provider (zonefile is portable)
- 🟢 **Terraform import** scaffolding (manually curate before applying)

YAML output captures: records, settings (SSL, HSTS, TLS versions, etc.),
DNSSEC state, and rulesets summary.

## File: scripts/cf-ips-fetch.sh

Pull current Cloudflare IP ranges (v4 + v6) and save to JSON for use by
app middleware that wants to allowlist origin traffic.

```bash
scripts/cf-ips-fetch.sh
# → .dns-state/_shared/cloudflare-ips.json
```

Run weekly via cron — Cloudflare changes their ranges occasionally.

## File: scripts/fly-restrict-origin.md

**Reference doc, not a script.** Walks through the three approaches to
restrict your Fly.io origin so it only accepts traffic from Cloudflare:

1. 🟢 App-level middleware (Node/Bun/Python examples)
2. 🟡 Caddy / nginx layer (if reverse-proxying)
3. 🔴 Cloudflare Tunnel (gold standard, requires `cloudflared`)

Includes gotchas (Fly health checks, third-party webhooks), test commands,
and rollout strategy. Read this BEFORE flipping the lock — misconfiguration
can lock you out of your own apps.

## File: scripts/lib.sh

Shared library — sourced by all the other scripts. Provides:

- `cf_api()` — Cloudflare API call with automatic global-key fallback
- `cf_global()` — explicit global-key call (for zone creation)
- `nc_get_hosts()`, `nc_set_nameservers()`, etc. — Namecheap helpers
- `cf_set_proxy()` — toggle orange/grey cloud
- `cf_upsert_record()` — create or update DNS record
- `state_dir()` — per-domain state directory under `.dns-state/`
