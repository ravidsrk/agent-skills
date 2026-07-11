## File: scripts/cf-ips-fetch.sh

Pull current Cloudflare IP ranges (v4 + v6) and save to JSON for use by
app middleware that wants to allowlist origin traffic.

```bash
scripts/cf-ips-fetch.sh
# → .dns-state/_shared/cloudflare-ips.json
```

Run weekly via cron — Cloudflare changes their ranges occasionally.
