############################################################
# Phase 4 — Edge & Access
#
# Order inside this config:
#   1. DNS zones (always on — needed for ACM validation)
#   2. CloudFront + WAF + public ACM
#   3. (Optional) Client VPN
#
# The ALB DNS names come from annotations on K8s Ingress; since
# those ALBs are created by the AWS LB Controller at apply-time
# of the kubectl manifests, they aren't known to Terraform until
# after the k8s manifests land. The DNS module handles this by
# accepting empty strings and skipping records until they're
# populated via var.primary_alb_dns_name / var.dr_alb_dns_name.
############################################################

############################################################
# Regional ACM certs — one for the public ALB, one for the
# internal ALB. The AWS Load Balancer Controller picks them up
# via the `alb.ingress.kubernetes.io/certificate-arn` annotation
# (read from Terraform output after apply).
############################################################

module "acm_public_alb" {
  source = "../../modules/acm"

  name            = "${local.name_prefix}-public-alb"
  domain_name     = "app.${var.domain_name}"
  route53_zone_id = module.dns.public_zone_id

  tags = local.common_tags
}

module "acm_internal_alb" {
  source = "../../modules/acm"

  name            = "${local.name_prefix}-internal-alb"
  domain_name     = "admin.${var.domain_name}"
  route53_zone_id = module.dns.public_zone_id

  tags = local.common_tags
}

module "dns" {
  source = "../../modules/dns"

  domain_name = var.domain_name
  vpc_id      = module.networking.vpc_id

  # Fill these in once the ALBs exist (after kubectl apply) and
  # re-run terraform apply to publish the failover records.
  primary_alb_dns_name  = var.primary_alb_dns_name
  primary_alb_zone_id   = var.primary_alb_zone_id
  internal_alb_dns_name = var.internal_alb_dns_name
  internal_alb_zone_id  = var.internal_alb_zone_id
  dr_alb_dns_name       = var.dr_alb_dns_name
  dr_alb_zone_id        = var.dr_alb_zone_id

  cloudfront_domain_name = var.enable_cloudfront ? module.cdn_waf[0].distribution_domain_name : ""
  cloudfront_zone_id     = var.enable_cloudfront ? module.cdn_waf[0].distribution_hosted_zone_id : "Z2FDTNDATAQYW2"

  ses_verification_token = module.sqs_lambda.ses_domain_verification_token
  ses_dkim_tokens        = module.sqs_lambda.ses_dkim_tokens

  tags = local.common_tags
}

# ----------------------------------------------------------
# CloudFront + WAF — optional. CloudFront needs an ALB origin.
# If the public ALB isn't up yet, leave enable_cloudfront = false
# and flip it on once the ALB exists.
# ----------------------------------------------------------

module "cdn_waf" {
  source = "../../modules/cdn-waf"
  count  = var.enable_cloudfront ? 1 : 0

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix     = local.name_prefix
  domain_name     = var.domain_name
  alb_dns_name    = var.primary_alb_dns_name
  route53_zone_id = module.dns.public_zone_id

  tags = local.common_tags
}

# ----------------------------------------------------------
# Client VPN — optional. $73/mo endpoint + $36/mo per subnet
# association + $0.05/hr per connection. Set enable_vpn=false
# to defer until needed.
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

  tags = local.common_tags
}
