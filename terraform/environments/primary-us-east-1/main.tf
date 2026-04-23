############################################################
# Primary environment — us-east-1
#
# Phase 1: Networking only.
# Subsequent phases will extend this file with ECR, RDS,
# ElastiCache, EKS, ALBs, Cognito, etc. — all consuming
# the outputs of module.networking.
############################################################

locals {
  name_prefix = "${var.project_name}-primary"

  common_tags = {
    Project     = "ShopCloud"
    Environment = var.environment
    Region      = var.primary_region
    ManagedBy   = "terraform"
    CostCenter  = "free-tier-optimized"
  }
}

data "aws_caller_identity" "current" {}

############################################################
# Phase 1 — Networking
############################################################

module "networking" {
  source = "../../modules/networking"

  name_prefix               = local.name_prefix
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
  eks_cluster_name          = var.eks_cluster_name
  vpn_client_cidr           = var.vpn_client_cidr

  enable_interface_endpoints = var.enable_interface_endpoints
  flow_logs_retention_days   = 7

  tags = local.common_tags
}
