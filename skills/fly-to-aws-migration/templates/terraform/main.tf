# Reusable Terraform foundation for Fly → AWS migration
# Battle-tested on a production migration (2026), Singapore region.
# Replace `var.project`, `var.environment`, `var.cloudflare_zone_id` with yours.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.42"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 🟡 Use S3 backend for shared state. Replace bucket name.
  # backend "s3" {
  #   bucket = "your-tf-state-bucket"
  #   key    = "your-app/terraform.tfstate"
  #   region = "ap-southeast-1"
  # }
}

# ── AWS provider — primary region (your stack) ──
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── AWS provider — us-east-1 alias for CloudFront cert ──
# 🔴 CRITICAL: CloudFront only reads certs from us-east-1
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ── Cloudflare provider ──
# Scoped API token (Zone:DNS:Edit + Zone:Cache Purge on the target zone).
# Global API key still works via the provider but is discouraged and not wired
# up here — create a token at https://dash.cloudflare.com/profile/api-tokens.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ── Variables ──
variable "project" {
  description = "Project slug (lowercase, hyphenated)"
  type        = string
}

variable "environment" {
  description = "Environment (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for your domain"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare scoped API token (Zone:DNS:Edit + Zone:Cache Purge)."
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Apex domain (e.g. example.com)"
  type        = string
}

variable "api_subdomain" {
  description = "Subdomain for API (e.g. api)"
  type        = string
  default     = "api"
}

# ── Common locals ──
locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ── Bucket suffix for uniqueness ──
resource "random_id" "bucket_suffix" {
  byte_length = 4
}
