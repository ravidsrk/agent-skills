# ALB with HTTPS listener for API.
# ACM cert is in primary region (NOT us-east-1 — that's only for CloudFront).

# Security group — allow HTTPS from anywhere
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB — HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_http2               = true
  enable_deletion_protection = false  # set true for prod after stable

  # Long keep-alive cuts handshake overhead
  idle_timeout = 60
}

# Target group — registers ECS tasks
resource "aws_lb_target_group" "api" {
  name                 = "${local.name_prefix}-api"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "ip"  # required for Fargate
  deregistration_delay = 30    # drain time on rolling deploys

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5   # be lenient — slow boots
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# ── ACM cert (in primary region, for ALB) ──
resource "aws_acm_certificate" "api" {
  domain_name       = "${var.api_subdomain}.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Cloudflare validation records
resource "cloudflare_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  value   = trimsuffix(each.value.record, ".")
  type    = each.value.type
  ttl     = 1     # auto
  proxied = false  # MUST be DNS-only for ACM validation
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in cloudflare_record.api_cert_validation : record.hostname]

  timeouts { create = "10m" }
}

# HTTP → HTTPS redirect
resource "aws_lb_listener" "api_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS listener
resource "aws_lb_listener" "api_https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_arn" { value = aws_lb.main.arn }
