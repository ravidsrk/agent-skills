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
