# Restricting Fly.io Origin to Cloudflare-Only Traffic

**Status:** documentation + reference scripts. Not auto-applied because misconfiguration can lock you out of your own apps.

# Why this matters

After enabling Cloudflare proxy + WAF + Bot Fight Mode + Rate Limiting on `example.com`, an attacker who knows the Fly hostname (`your-app.fly.dev`) can **bypass Cloudflare entirely** and hit your origin directly. They get:

- 🔴 No WAF rules blocking SQLi/XSS/exploits
- 🔴 No DDoS protection at L7
- 🔴 No rate limiting
- 🔴 No bot fighting

Restricting your origin to accept only traffic from Cloudflare's published IP ranges closes this gap.

# Cloudflare's IP ranges

Updated regularly by Cloudflare. Always pull fresh:

```bash
# IPv4
curl -s https://www.cloudflare.com/ips-v4 | sort -V

# IPv6
curl -s https://www.cloudflare.com/ips-v6 | sort -V
```

As of 2026-05-02, this is ~17 IPv4 ranges + 7 IPv6 ranges. They change occasionally — pin a refresh schedule (e.g. weekly via cron).

# Three approaches to restrict (pick based on your stack)

# 🔴 Option 1: App-level middleware (RECOMMENDED for Fly)

Add a middleware that drops requests where the source IP isn't in Cloudflare's ranges. This is the cleanest because:
- Survives Fly platform changes
- You control failure mode (return 403, log, etc.)
- Works for any app type (Node/Python/Go/Bun/Deno)
- Can ALLOW health-checks from specific known IPs
- Trusts `cf-connecting-ip` to recover the real client IP for downstream code

# Node/Express example

```javascript
import express from 'express';
import { readFileSync } from 'node:fs';

const CF_RANGES_V4 = await fetch('https://www.cloudflare.com/ips-v4').then(r => r.text())
  .then(t => t.trim().split('\n'));
const CF_RANGES_V6 = await fetch('https://www.cloudflare.com/ips-v6').then(r => r.text())
  .then(t => t.trim().split('\n'));

const ALLOWLIST = [
  ...CF_RANGES_V4,
  ...CF_RANGES_V6,
  // Allow Fly's internal health checks
  '10.0.0.0/8',          // Fly private 6PN
  'fdaa::/16',           // Fly private IPv6
];

import ipRangeCheck from 'ip-range-check';

const app = express();
app.set('trust proxy', true);

app.use((req, res, next) => {
  const ip = req.ip || req.connection.remoteAddress;
  if (!ipRangeCheck(ip, ALLOWLIST)) {
    console.warn(`Blocked direct origin access from ${ip}`);
    return res.status(403).send('Direct origin access not allowed.');
  }
  // For app code, use the real client IP from CF
  req.realIp = req.headers['cf-connecting-ip'] || ip;
  next();
});
```

# Bun / Hono example

```typescript
import { Hono } from 'hono';
import { ipRestriction } from 'hono/ip-restriction';

const cfV4 = await fetch('https://www.cloudflare.com/ips-v4').then(r => r.text())
  .then(t => t.trim().split('\n'));
const cfV6 = await fetch('https://www.cloudflare.com/ips-v6').then(r => r.text())
  .then(t => t.trim().split('\n'));

const app = new Hono();

app.use('*', ipRestriction(
  (c) => c.req.header('fly-client-ip') ?? '',
  { allowList: [...cfV4, ...cfV6, '10.0.0.0/8'] }
));
```

# Python/FastAPI example

```python
from fastapi import FastAPI, Request, HTTPException
import ipaddress, httpx

CF_V4 = httpx.get("https://www.cloudflare.com/ips-v4").text.strip().split("\n")
CF_V6 = httpx.get("https://www.cloudflare.com/ips-v6").text.strip().split("\n")
ALLOW = [ipaddress.ip_network(c) for c in CF_V4 + CF_V6] + [ipaddress.ip_network("10.0.0.0/8")]

app = FastAPI()

@app.middleware("http")
async def cf_only(request: Request, call_next):
    ip = ipaddress.ip_address(request.client.host)
    if not any(ip in net for net in ALLOW):
        raise HTTPException(403, "Direct origin access not allowed")
    return await call_next(request)
```

# 🟡 Option 2: Caddy / nginx layer (if you run a reverse proxy)

If your Fly app uses Caddy or nginx in front:

# nginx.conf

```nginx
# Auto-fetch Cloudflare IPs at config-reload time:
include /etc/nginx/cloudflare-ips.conf;   # generate this from `curl https://www.cloudflare.com/ips-v4`

server {
    listen 443 ssl http2;
    server_name example.com;

    # Trust X-Forwarded-For from Cloudflare
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    # ... (full list from https://www.cloudflare.com/ips-v4)
    real_ip_header CF-Connecting-IP;

    # Default: deny
    deny all;

    # Allow only from CF ranges
    allow 173.245.48.0/20;
    allow 103.21.244.0/22;
    # ... (full list)
}
```

# Caddyfile

```
example.com {
    @cf {
        client_ip 173.245.48.0/20 103.21.244.0/22 # ... etc
    }
    handle @cf {
        reverse_proxy localhost:3000
    }
    handle {
        respond "Direct origin access not allowed" 403
    }
}
```

# 🟢 Option 3: Fly internal-only services (BEST when feasible)

Make your Fly app itself **not directly internet-reachable**. Cloudflare connects via a tunnel.

**Cloudflare Tunnel approach:**
1. Fly app has no public IP (only Fly private 6PN)
2. Run `cloudflared` as a sidecar inside the app's machine
3. Cloudflare → cloudflared tunnel → app on localhost
4. Result: zero public exposure of origin

This is the gold standard but requires running `cloudflared` inside Fly machines. Setup:

```bash
# 1. Install cloudflared on a CF-account-level token
cloudflared tunnel login
cloudflared tunnel create your-app-tunnel

# 2. Add tunnel config to fly.toml or as a sidecar
# (cloudflared listens on :8080, forwards to localhost:3000)

# 3. CNAME example.com → <tunnel-id>.cfargotunnel.com  (handled via CF dashboard)

# 4. Remove the Fly public IP (fly ips release ...)
```

# Helper: pull Cloudflare IPs into a JSON file

```bash
#!/bin/bash
# Save Cloudflare IPs for use in app middleware
mkdir -p .dns-state/_shared
{
  echo '{'
  echo '  "v4": ['
  curl -s https://www.cloudflare.com/ips-v4 | awk 'NF {printf "    \"%s\"%s\n", $0, (NR==17?"":",")}'
  echo '  ],'
  echo '  "v6": ['
  curl -s https://www.cloudflare.com/ips-v6 | awk 'NF {printf "    \"%s\"%s\n", $0, (NR==7?"":",")}'
  echo '  ],'
  echo '  "updated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"'
  echo '}'
} > .dns-state/_shared/cloudflare-ips.json
```

# What NOT to do

- 🔴 **Don't restrict via Fly's `services.ports.handlers` to specific IPs.** Fly's TLS handler doesn't support source-IP allowlisting; you'd block legitimate health checks.
- 🔴 **Don't drop the Fly public hostname access entirely** unless you're certain Cloudflare is the only path. Test thoroughly first.
- 🔴 **Don't forget Fly health checks.** Fly probes from internal IPs (10.0.0.0/8, fdaa::/16) — keep those allowed.
- 🟡 **Don't forget any third-party webhook endpoints** (Stripe, GitHub, etc.) — they hit your origin from non-CF IPs. Either route those through CF too, or add their IP ranges to the allowlist.

# Recommended path for example.com specifically

Looking at the Fly toml setup from the codebase audit:
1. `your-web-app.fly.dev` (web/Next.js)
2. `your-app.fly.dev` (API)
3. `your-docs-app.fly.dev` (docs)

For each:

1. **Add the IP-allowlist middleware to the app code** (Option 1) — most flexible
2. **Test with `curl --resolve example.com:443:<fly-ip> https://example.com/`** before and after — should return 403 after
3. **Test via Cloudflare** — `curl https://example.com/` should still return 200
4. Watch logs for any legitimate traffic getting blocked (third-party webhooks, monitoring services)
5. Add exceptions to the allowlist as needed

# Verification

After applying:

```bash
# 1. Direct hit on Fly should fail (403):
curl -sI -H "Host: example.com" https://your-app.fly.dev/

# 2. Through Cloudflare should succeed (200):
curl -sI https://example.com/

# 3. From a known third-party (e.g. webhook simulator):
# Adjust allowlist if it 403s.
```

# When to revisit

- **CF IP ranges change** → refresh weekly (cron job inside the app, or rebuild + redeploy)
- **New webhook integration** → add the integration's source IPs to the allowlist
- **Outage debugging** → temporarily disable the middleware via env var (e.g. `BYPASS_ORIGIN_LOCK=true`)
