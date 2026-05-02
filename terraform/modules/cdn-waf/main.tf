############################################################
# CloudFront + WAF v2 (CLOUDFRONT scope in us-east-1).
#
# Works in two modes:
#   - Without domain (route53_zone_id = ""): uses the default
#     *.cloudfront.net hostname + CloudFront's own TLS cert.
#     No ACM or Route 53 required.
#   - With domain (route53_zone_id set): adds custom aliases
#     (<domain> and app.<domain>), an ACM cert, and writes DNS validation
#     records into Route 53.
############################################################

locals {
  tags              = merge(var.tags, { Module = "cdn-waf" })
  use_custom_domain = var.route53_zone_id != ""
  cf_aliases        = local.use_custom_domain ? [var.domain_name, "app.${var.domain_name}"] : []
}

# ----------------------------------------------------------
# ACM certificate for CloudFront (only when custom domain)
# ----------------------------------------------------------

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1
  count    = local.use_custom_domain ? 1 : 0

  domain_name               = "app.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-cloudfront-cert" })
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.use_custom_domain ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1
  count    = local.use_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ----------------------------------------------------------
# WAF v2 - CLOUDFRONT scope, must live in us-east-1
# ----------------------------------------------------------

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1

  name        = "${var.name_prefix}-cf-waf"
  description = "ShopCloud WAF for CloudFront - core rules + rate limit"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCommon"
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesSQLiRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSSQLi"
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSBadInputs"
    }
  }

  rule {
    name     = "RateLimit"
    priority = 40
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cf-waf"
  }

  tags = local.tags
}

# ----------------------------------------------------------
# CloudFront distribution (PriceClass_100)
# ----------------------------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name_prefix} CloudFront distribution"
  price_class     = "PriceClass_100"
  aliases         = local.cf_aliases
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn
  http_version    = "http2and3"

  origin {
    domain_name = var.alb_dns_name
    origin_id   = "regional-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "regional-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed policies
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer
  }

  viewer_certificate {
    # Custom domain: use ACM cert with SNI.
    # No domain: use CloudFront's own *.cloudfront.net cert (free, no config needed).
    acm_certificate_arn            = local.use_custom_domain ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_custom_domain ? "TLSv1.2_2021" : "TLSv1.2_2021"
    cloudfront_default_certificate = !local.use_custom_domain
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-cf" })
}
