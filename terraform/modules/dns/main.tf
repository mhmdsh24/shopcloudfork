############################################################
# DNS - public + private hosted zones, latency records,
# SES DKIM/SPF/DMARC.
############################################################

locals {
  tags = merge(var.tags, { Module = "dns" })
}

# ----------------------------------------------------------
# Public hosted zone - $0.50/mo
# ----------------------------------------------------------

resource "aws_route53_zone" "public" {
  name = var.domain_name
  tags = merge(local.tags, { Name = var.domain_name })
}

# ----------------------------------------------------------
# Private hosted zone - free, associated with the VPC
# ----------------------------------------------------------

resource "aws_route53_zone" "private" {
  name = "internal.${var.domain_name}"

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(local.tags, { Name = "internal.${var.domain_name}" })
}

# ----------------------------------------------------------
# Latency-based A-alias records for app.<domain>
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

  latency_routing_policy {
    region = var.primary_region
  }

  alias {
    name                   = local.use_cf ? var.cloudfront_domain_name : var.primary_alb_dns_name
    zone_id                = local.use_cf ? var.cloudfront_zone_id : var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_dr" {
  count = (local.use_cf || var.dr_alb_dns_name != "") ? 1 : 0

  zone_id        = aws_route53_zone.public.zone_id
  name           = "app.${var.domain_name}"
  type           = "A"
  set_identifier = "secondary-eu-west-1"

  latency_routing_policy {
    region = var.dr_region
  }

  alias {
    name                   = local.use_cf ? var.cloudfront_domain_name : var.dr_alb_dns_name
    zone_id                = local.use_cf ? var.cloudfront_zone_id : var.dr_alb_zone_id
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
# SES - DKIM CNAMEs + SPF TXT + DMARC TXT + verification TXT
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
