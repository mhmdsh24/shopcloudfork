############################################################
# Phase 4 - Edge & Access
#
# Every resource below is gated by `var.enable_domain`. Set it
# to `false` (the default) while you don't own a real domain -
# Terraform will then skip:
#
#   * the Route 53 public + private hosted zones and all records
#   * the two regional ACM certs (public ALB + internal ALB)
#   * CloudFront custom domain + its ACM cert (via enable_cloudfront)
#
# Pods still serve traffic - the AWS Load Balancer Controller
# will create ALBs with the default `*.us-east-1.elb.amazonaws.com`
# hostnames over plain HTTP. Flip `enable_domain = true` once
# you own a domain and delegate its NS to Route 53.
############################################################

############################################################
# Regional ACM certs - one for the public ALB, one for the
# internal ALB. The AWS Load Balancer Controller picks them up
# via the `alb.ingress.kubernetes.io/certificate-arn` annotation
# (read from Terraform output after apply).
############################################################

module "acm_public_alb" {
  source = "../../modules/acm"
  count  = var.enable_domain ? 1 : 0

  name            = "${local.name_prefix}-public-alb"
  domain_name     = "app.${var.domain_name}"
  route53_zone_id = module.dns[0].public_zone_id

  tags = local.common_tags
}

module "acm_internal_alb" {
  source = "../../modules/acm"
  count  = var.enable_domain ? 1 : 0

  name            = "${local.name_prefix}-internal-alb"
  domain_name     = "admin.internal.${var.domain_name}"
  route53_zone_id = module.dns[0].public_zone_id

  tags = local.common_tags
}

############################################################
# Route 53 - public zone, private zone, latency records,
# SES DKIM/SPF/DMARC. All of this depends on owning the
# domain (validation records need to resolve on the open
# internet), so it's gated behind the same flag.
############################################################

module "dns" {
  source = "../../modules/dns"
  count  = var.enable_domain ? 1 : 0

  domain_name = var.domain_name
  vpc_id      = module.networking.vpc_id

  # Fill these in once the ALBs exist (after kubectl apply) and
  # re-run terraform apply to publish the latency records.
  primary_alb_dns_name  = var.primary_alb_dns_name
  primary_alb_zone_id   = var.primary_alb_zone_id
  primary_region        = var.primary_region
  internal_alb_dns_name = var.internal_alb_dns_name
  internal_alb_zone_id  = var.internal_alb_zone_id
  dr_alb_dns_name       = var.dr_alb_dns_name
  dr_alb_zone_id        = var.dr_alb_zone_id
  dr_region             = var.dr_region

  cloudfront_domain_name = var.enable_cloudfront ? module.cdn_waf[0].distribution_domain_name : ""
  cloudfront_zone_id     = var.enable_cloudfront ? module.cdn_waf[0].distribution_hosted_zone_id : "Z2FDTNDATAQYW2"

  ses_verification_token = module.sqs_lambda.ses_domain_verification_token
  ses_dkim_tokens        = module.sqs_lambda.ses_dkim_tokens

  tags = local.common_tags
}

# ----------------------------------------------------------
# CloudFront + WAF - optional, AND requires enable_domain=true
# because the custom alias + ACM cert both depend on a real
# public zone. WAF itself doesn't need a domain; if you want
# WAF without the domain stack, flip the count on just the
# WAF resource inside modules/cdn-waf.
# ----------------------------------------------------------

module "cdn_waf" {
  source = "../../modules/cdn-waf"
  count  = var.enable_cloudfront && var.enable_domain ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = local.name_prefix
  domain_name     = var.domain_name
  alb_dns_name    = var.primary_alb_dns_name
  route53_zone_id = module.dns[0].public_zone_id

  tags = local.common_tags
}

# ----------------------------------------------------------
# Client VPN - independent of the domain toggle; gated by its
# own `enable_vpn` flag.
# ----------------------------------------------------------

module "vpn" {
  source = "../../modules/vpn"
  count  = var.enable_vpn ? 1 : 0

  name_prefix = local.name_prefix
  client_cidr = var.vpn_client_cidr

  subnet_id              = module.networking.private_app_subnet_ids[0]
  vpc_security_group_ids = [module.networking.security_group_ids.vpn]
  authorized_cidrs = [
    module.networking.vpc_cidr,
  ]

  server_certificate_arn      = var.vpn_server_certificate_arn
  client_root_certificate_arn = var.vpn_client_root_certificate_arn
  mfa_saml_provider_arn       = var.vpn_mfa_saml_provider_arn

  tags = local.common_tags
}
