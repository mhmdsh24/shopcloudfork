############################################################
# DNS - public + private hosted zones, latency records,
# SES DKIM/SPF/DMARC.
############################################################

locals {
  tags                      = merge(var.tags, { Module = "dns" })
  use_existing_public_zone  = trimspace(var.public_zone_id) != ""
  public_zone_id            = local.use_existing_public_zone ? data.aws_route53_zone.public[0].zone_id : aws_route53_zone.public[0].zone_id
  public_zone_name_servers  = local.use_existing_public_zone ? data.aws_route53_zone.public[0].name_servers : aws_route53_zone.public[0].name_servers
  public_hostnames          = toset([var.domain_name, "app.${var.domain_name}"])
  origin_hostname           = "origin.${var.domain_name}"
  has_primary_alb_alias     = trimspace(var.primary_alb_dns_name) != "" && trimspace(var.primary_alb_zone_id) != ""
  has_dr_alb_alias          = trimspace(var.dr_alb_dns_name) != "" && trimspace(var.dr_alb_zone_id) != ""
  use_regional_alb_latency  = local.has_primary_alb_alias && local.has_dr_alb_alias
  use_cloudfront_public     = var.enable_cloudfront_public_alias
  use_cloudfront_origin_lbr = local.use_cloudfront_public && local.use_regional_alb_latency
  use_direct_alb_public     = !local.use_cloudfront_public && local.has_primary_alb_alias
  public_routing_mode = (
    local.use_cloudfront_origin_lbr ? "cloudfront-regional-origin-latency" :
    local.use_cloudfront_public ? "cloudfront-primary-origin" :
    local.use_regional_alb_latency ? "regional-alb-latency" :
    local.has_primary_alb_alias ? "primary-alb-only" :
    "disabled"
  )
}

# ----------------------------------------------------------
# Public hosted zone - use an existing zone when the domain was
# registered through Route 53, otherwise create one.
# ----------------------------------------------------------

resource "aws_route53_zone" "public" {
  count = local.use_existing_public_zone ? 0 : 1

  name = var.domain_name
  tags = merge(local.tags, { Name = var.domain_name })
}

data "aws_route53_zone" "public" {
  count   = local.use_existing_public_zone ? 1 : 0
  zone_id = var.public_zone_id
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
# Public A-alias records for the apex and app.<domain>.
#
# Preferred active-active mode:
#   apex/app -> CloudFront
#   CloudFront origin -> origin.<domain>
#   origin.<domain> -> regional ALBs with latency routing
#
# Fallback mode when CloudFront is off:
#   apex/app -> regional ALBs with latency routing
# ----------------------------------------------------------

resource "aws_route53_record" "public_primary" {
  for_each = local.use_cloudfront_public || local.use_direct_alb_public ? local.public_hostnames : toset([])

  zone_id = local.public_zone_id
  name    = each.value
  type    = "A"

  set_identifier = local.use_cloudfront_public ? null : "primary-${var.primary_region}"

  dynamic "latency_routing_policy" {
    for_each = local.use_cloudfront_public ? [] : [var.primary_region]

    content {
      region = latency_routing_policy.value
    }
  }

  alias {
    name                   = local.use_cloudfront_public ? var.cloudfront_domain_name : var.primary_alb_dns_name
    zone_id                = local.use_cloudfront_public ? var.cloudfront_zone_id : var.primary_alb_zone_id
    evaluate_target_health = !local.use_cloudfront_public
  }
}

resource "aws_route53_record" "public_dr" {
  for_each = !local.use_cloudfront_public && local.use_regional_alb_latency ? local.public_hostnames : toset([])

  zone_id        = local.public_zone_id
  name           = each.value
  type           = "A"
  set_identifier = "secondary-${var.dr_region}"

  latency_routing_policy {
    region = var.dr_region
  }

  alias {
    name                   = var.dr_alb_dns_name
    zone_id                = var.dr_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "origin_primary" {
  count = local.use_cloudfront_origin_lbr ? 1 : 0

  zone_id        = local.public_zone_id
  name           = local.origin_hostname
  type           = "A"
  set_identifier = "origin-primary-${var.primary_region}"

  latency_routing_policy {
    region = var.primary_region
  }

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "origin_dr" {
  count = local.use_cloudfront_origin_lbr ? 1 : 0

  zone_id        = local.public_zone_id
  name           = local.origin_hostname
  type           = "A"
  set_identifier = "origin-secondary-${var.dr_region}"

  latency_routing_policy {
    region = var.dr_region
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
# SES - DKIM CNAMEs + SPF TXT + DMARC TXT + verification TXT
# ----------------------------------------------------------

resource "aws_route53_record" "ses_verification" {
  count = var.enable_ses_records ? 1 : 0

  zone_id = local.public_zone_id
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

  zone_id = local.public_zone_id
  name    = "${var.ses_dkim_tokens[tonumber(each.key)]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${var.ses_dkim_tokens[tonumber(each.key)]}.dkim.amazonses.com"]
}

resource "aws_route53_record" "spf" {
  zone_id = local.public_zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com -all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = local.public_zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=reject; rua=mailto:dmarc@${var.domain_name}"]
}
