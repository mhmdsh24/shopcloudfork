############################################################
# Phase 5 — DR region — ALB + WAF + ECS Fargate (scale from 0)
#
# Uses the Secrets Manager replicas created by the primary
# region (regions match by name, not ARN).
############################################################

locals {
  replicated_secret_prefix = "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret"

  db_secret_arn_dr      = "${local.replicated_secret_prefix}:shopcloud/db/master"
  redis_secret_arn_dr   = "${local.replicated_secret_prefix}:shopcloud/redis/auth"
  cognito_secret_arn_dr = "${local.replicated_secret_prefix}:shopcloud/cognito/config"
}

# ----------------------------------------------------------
# ACM cert for DR ALB (optional; leave domain_name = "" to skip)
# ----------------------------------------------------------

resource "aws_acm_certificate" "dr_alb" {
  count = var.dr_alb_domain_name != "" ? 1 : 0

  domain_name       = var.dr_alb_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# The primary region owns the public hosted zone. Validation
# records are created there (pasted in as outputs, or applied
# manually). For now we expose the validation fields so the
# operator can plumb them into Route 53.

# ----------------------------------------------------------
# DR module — ALB + WAF + ECS Fargate scale-from-zero
# ----------------------------------------------------------

module "dr" {
  source = "../../modules/dr"

  name_prefix = local.name_prefix

  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_app_subnet_ids = module.networking.private_app_subnet_ids

  public_alb_sg_id = module.networking.security_group_ids.public_alb
  eks_nodes_sg_id  = module.networking.security_group_ids.eks_nodes

  account_id = data.aws_caller_identity.current.account_id
  region     = var.dr_region

  # Whether to attach an HTTPS listener is a static (plan-time) choice
  # driven by whether the user supplied dr_alb_domain_name in tfvars.
  enable_https_listener = var.dr_alb_domain_name != ""
  alb_certificate_arn   = try(aws_acm_certificate.dr_alb[0].arn, "")

  db_secret_arn      = local.db_secret_arn_dr
  redis_secret_arn   = local.redis_secret_arn_dr
  cognito_secret_arn = local.cognito_secret_arn_dr

  tags = local.common_tags
}
