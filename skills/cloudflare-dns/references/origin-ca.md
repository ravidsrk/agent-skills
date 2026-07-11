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
