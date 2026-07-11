## File: scripts/lib.sh

Shared library — sourced by all the other scripts. Provides:

- `cf_api()` — Cloudflare API call with automatic global-key fallback
- `cf_global()` — explicit global-key call (for zone creation)
- `nc_get_hosts()`, `nc_set_nameservers()`, etc. — Namecheap helpers
- `cf_set_proxy()` — toggle orange/grey cloud
- `cf_upsert_record()` — create or update DNS record
- `state_dir()` — per-domain state directory under `.dns-state/`
