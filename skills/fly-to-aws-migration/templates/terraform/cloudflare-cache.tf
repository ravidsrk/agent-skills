# Cloudflare cache layer for static sites — Phase 7 perf tuning.
# Cuts TTFB ~4.8x for repeat visitors. $0/mo.
#
# 🟡 Cloudflare quirk: entrypoint ruleset MUST be named "default"

# Tiered cache — free regional cache layer
resource "cloudflare_tiered_cache" "main" {
  zone_id    = var.cloudflare_zone_id
  cache_type = "smart" # Cloudflare picks best upper-tier datacenter
}

# 🔴 Do NOT use cloudflare_argo resource — it's deprecated AND requires
# a paid Argo subscription. cloudflare_tiered_cache alone is free.

# Cache rule — force edge cache for HTML responses
resource "cloudflare_ruleset" "static_sites_cache" {
  zone_id     = var.cloudflare_zone_id
  name        = "default" # 🟡 entrypoint singletons MUST be "default"
  description = "Edge-cache HTML for static sites (respect origin TTL)"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    description = "Cache HTML at edge — respect S3 origin Cache-Control"
    enabled     = true
    expression = join(" or ", [
      for alias in local.all_aliases :
      "(http.host eq \"${alias}\")"
    ])
    action = "set_cache_settings"

    action_parameters {
      cache = true

      edge_ttl {
        mode = "respect_origin" # uses S3-uploaded Cache-Control headers
      }

      browser_ttl {
        mode = "respect_origin"
      }
    }
  }
}
