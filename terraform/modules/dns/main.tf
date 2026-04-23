############################################################
# DNS — public + private hosted zones, failover records,
# SES DKIM/SPF/DMARC, health checks.
############################################################

locals {
  tags = merge(var.tags, { Module = "dns" })
}

# ----------------------------------------------------------
# Public hosted zone — $0.50/mo
# ----------------------------------------------------------

resource "aws_route53_zone" "public" {
  name = var.domain_name
  tags = merge(local.tags, { Name = var.domain_name })
}

# ----------------------------------------------------------
# Private hosted zone — free, associated with the VPC
# ----------------------------------------------------------

resource "aws_route53_zone" "private" {
  name = "internal.${var.domain_name}"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(local.tags, { Name = "internal.${var.domain_name}" })
}

# ----------------------------------------------------------
# Health check on the primary ALB — drives failover
# ----------------------------------------------------------

resource "aws_route53_health_check" "primary" {
  count = var.primary_alb_dns_name != "" ? 1 : 0

  fqdn              = var.primary_alb_dns_name
  type              = "HTTPS"
  resource_path     = "/healthz"
  port              = 443
  request_interval  = 30
  failure_threshold = 3

  tags = merge(local.tags, { Name = "shopcloud-primary-healthcheck" })
}

# ----------------------------------------------------------
# Failover A-alias records for app.<domain>
#
# Primary points to CloudFront (which sits in front of primary
# ALB); Secondary points directly at the DR ALB. If CloudFront
# isn't used, set cloudfront_domain_name empty and the primary
# will alias to the primary ALB instead.
# ----------------------------------------------------------

locals {
  use_cf = var.cloudfront_domain_name != ""
}

resource "aws_route53_record" "app_primary" {
  count = (local.use_cf || var.primary_alb_dns_name != "") ? 1 : 0

  zone_id        = aws_route53_zone.public.zone_id
  name           = "app.${var.domain_name}"
  type           = "A"
  set_identifier = "primary-us-east-1"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = var.primary_alb_dns_name != "" ? aws_route53_health_check.primary[0].id : null

  alias {
    name                   = local.use_cf ? var.cloudfront_domain_name : var.primary_alb_dns_name
    zone_id                = local.use_cf ? var.cloudfront_zone_id : var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_dr" {
  count = var.dr_alb_dns_name != "" ? 1 : 0

  zone_id        = aws_route53_zone.public.zone_id
  name           = "app.${var.domain_name}"
  type           = "A"
  set_identifier = "secondary-eu-west-1"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.dr_alb_dns_name
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}

# ----------------------------------------------------------
# Private alias: admin.internal.<domain> -> internal ALB
# ----------------------------------------------------------

resource "aws_route53_record" "admin_internal" {
  count = var.internal_alb_dns_name != "" ? 1 : 0

  zone_id = aws_route53_zone.private.zone_id
  name    = "admin.internal.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.internal_alb_dns_name
    zone_id                = var.internal_alb_zone_id
    evaluate_target_health = false
  }
}

# ----------------------------------------------------------
# SES — DKIM CNAMEs + SPF TXT + DMARC TXT + verification TXT
# ----------------------------------------------------------

resource "aws_route53_record" "ses_verification" {
  count = var.enable_ses_records ? 1 : 0

  zone_id = aws_route53_zone.public.zone_id
  name    = "_amazonses.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = [var.ses_verification_token]
}

# aws_ses_domain_dkim always returns exactly three tokens; iterate over a
# static set of keys so the for_each map is known at plan time, then index
# into the (computed) tokens at apply time.
resource "aws_route53_record" "ses_dkim" {
  for_each = var.enable_ses_records ? toset(["0", "1", "2"]) : toset([])

  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.ses_dkim_tokens[tonumber(each.key)]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${var.ses_dkim_tokens[tonumber(each.key)]}.dkim.amazonses.com"]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.public.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=reject; rua=mailto:dmarc@${var.domain_name}"]
}
