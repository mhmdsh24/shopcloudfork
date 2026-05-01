############################################################
# DNS - public + private hosted zones, latency records,
# SES DKIM/SPF/DMARC.
############################################################

locals {
  tags                       = merge(var.tags, { Module = "dns" })
  use_existing_public_zone   = trimspace(var.public_zone_id) != ""
  public_zone_id             = local.use_existing_public_zone ? data.aws_route53_zone.public[0].zone_id : aws_route53_zone.public[0].zone_id
  public_zone_name_servers   = local.use_existing_public_zone ? data.aws_route53_zone.public[0].name_servers : aws_route53_zone.public[0].name_servers
  public_hostnames           = toset([var.domain_name, "app.${var.domain_name}"])
  use_cf                     = trimspace(var.cloudfront_domain_name) != ""
  has_primary_public_alias   = local.use_cf || trimspace(var.primary_alb_dns_name) != ""
  has_secondary_public_alias = !local.use_cf && trimspace(var.dr_alb_dns_name) != ""
  primary_alias_name         = local.use_cf ? var.cloudfront_domain_name : var.primary_alb_dns_name
  primary_alias_zone_id      = local.use_cf ? var.cloudfront_zone_id : var.primary_alb_zone_id
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
# Latency-based A-alias records for the apex and app.<domain>.
# ----------------------------------------------------------

resource "aws_route53_record" "public_primary" {
  for_each = local.has_primary_public_alias ? local.public_hostnames : toset([])

  zone_id        = local.public_zone_id
  name           = each.value
  type           = "A"
  set_identifier = "primary-${var.primary_region}"

  latency_routing_policy {
    region = var.primary_region
  }

  alias {
    name                   = local.primary_alias_name
    zone_id                = local.primary_alias_zone_id
    evaluate_target_health = local.use_cf ? false : true
  }
}

resource "aws_route53_record" "public_dr" {
  for_each = local.has_secondary_public_alias ? local.public_hostnames : toset([])

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
