# Static sites — S3 + CloudFront with single cert.
# 🔴 Cert MUST be in us-east-1 (the `aws.us-east-1` provider alias).
#
# Pattern: 1 cert with all SANs, N CloudFront distributions sharing the cert.

variable "static_sites" {
  description = "Static sites to deploy. Each site gets its own S3 bucket + CloudFront distribution."
  type = map(object({
    aliases = list(string) # domains served by this distribution
  }))
  default = {
    web = {
      aliases = ["yourdomain.com", "www.yourdomain.com"]
    }
    docs = {
      aliases = ["docs.yourdomain.com"]
    }
  }
}

variable "primary_domain" {
  description = "The apex domain used as the ACM cert's primary CommonName. All other aliases become SANs. Explicit so cert layout isn't sensitive to map ordering."
  type        = string
}

locals {
  # Flatten all aliases across all sites for the single cert. Order the primary
  # domain first so it's the cert's CN; SANs are everything else.
  all_aliases         = distinct(flatten([for k, v in var.static_sites : v.aliases]))
  cert_san_candidates = [for a in local.all_aliases : a if a != var.primary_domain]
}

# ── ACM cert in us-east-1 — REQUIRED for CloudFront ──
resource "aws_acm_certificate" "sites" {
  provider = aws.us-east-1 # 🔴 CRITICAL

  domain_name               = var.primary_domain
  subject_alternative_names = local.cert_san_candidates
  validation_method         = "DNS"

  lifecycle { create_before_destroy = true }
}

resource "cloudflare_record" "sites_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.sites.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  value   = trimsuffix(each.value.record, ".")
  type    = each.value.type
  ttl     = 1
  proxied = false # DNS-only for validation
}

resource "aws_acm_certificate_validation" "sites" {
  provider = aws.us-east-1

  certificate_arn         = aws_acm_certificate.sites.arn
  validation_record_fqdns = [for r in cloudflare_record.sites_cert_validation : r.hostname]
}

# ── S3 buckets (private, OAC-only) ──
resource "aws_s3_bucket" "site" {
  for_each = var.static_sites

  bucket        = "${local.name_prefix}-site-${each.key}-${random_id.bucket_suffix.hex}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "site" {
  for_each = aws_s3_bucket.site
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  for_each = aws_s3_bucket.site
  bucket   = each.value.id

  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  for_each = aws_s3_bucket.site
  bucket   = each.value.id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ── CloudFront ──
resource "aws_cloudfront_origin_access_control" "site" {
  for_each = var.static_sites

  name                              = "${local.name_prefix}-site-${each.key}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Response headers policy — security headers
resource "aws_cloudfront_response_headers_policy" "site" {
  name = "${local.name_prefix}-site-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000 # 2 years
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# CloudFront function — rewrite /foo → /foo.html for Next.js static export
resource "aws_cloudfront_function" "html_rewrite" {
  name    = "${local.name_prefix}-html-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "URI rewrite for Next.js static export — /foo → /foo.html"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Don't touch URIs with file extensions or _next/static assets
      if (uri.includes('.') || uri.startsWith('/_next/')) {
        return request;
      }

      // Root: index.html
      if (uri === '/') {
        request.uri = '/index.html';
        return request;
      }

      // Trailing slash: try /foo/index.html
      if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
        return request;
      }

      // /foo → /foo.html
      request.uri = uri + '.html';
      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "site" {
  for_each = var.static_sites

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = "PriceClass_100" # NA+EU only = cheapest
  aliases             = each.value.aliases
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.site[each.key].bucket_regional_domain_name
    origin_id                = "s3-${each.key}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site[each.key].id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${each.key}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized (AWS managed)
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.html_rewrite.arn
    }
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.sites.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ── S3 bucket policy — only CloudFront can read ──
data "aws_iam_policy_document" "site_bucket" {
  for_each = var.static_sites

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site[each.key].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  for_each = var.static_sites
  bucket   = aws_s3_bucket.site[each.key].id
  policy   = data.aws_iam_policy_document.site_bucket[each.key].json
}

output "site_bucket_names" {
  value = { for k, v in aws_s3_bucket.site : k => v.id }
}

output "site_cloudfront_ids" {
  value = { for k, v in aws_cloudfront_distribution.site : k => v.id }
}

output "site_cloudfront_domains" {
  value = { for k, v in aws_cloudfront_distribution.site : k => v.domain_name }
}
