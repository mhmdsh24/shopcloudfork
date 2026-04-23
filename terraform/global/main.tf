############################################################
# Global (cross-region) configuration
#
# This config pulls the outputs of the two regional environments
# via remote state and connects them with a VPC peering connection.
#
# Execution order:
#   1. terraform apply  in terraform/environments/primary-us-east-1
#   2. terraform apply  in terraform/environments/dr-eu-west-1
#   3. terraform apply  in terraform/global        <- this config
############################################################

locals {
  common_tags = {
    Project     = "ShopCloud"
    Environment = var.environment
    ManagedBy   = "terraform"
    Scope       = "global"
    CostCenter  = "free-tier-optimized"
  }
}

# ---- Remote state of the two regional environments -----

data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "primary-us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "dr" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "dr-eu-west-1/terraform.tfstate"
    region = "us-east-1"
  }
}

############################################################
# Phase 1 - Cross-region VPC peering (primary <-> DR)
############################################################

module "peering" {
  source = "../modules/peering"

  providers = {
    aws.requester = aws.primary
    aws.accepter  = aws.dr
  }

  name = "${var.project_name}-primary-to-dr"

  requester_vpc_id   = data.terraform_remote_state.primary.outputs.vpc_id
  requester_vpc_cidr = data.terraform_remote_state.primary.outputs.vpc_cidr
  requester_route_table_ids = [
    data.terraform_remote_state.primary.outputs.public_route_table_id,
    data.terraform_remote_state.primary.outputs.private_app_route_table_id,
    data.terraform_remote_state.primary.outputs.private_data_route_table_id,
  ]

  accepter_vpc_id   = data.terraform_remote_state.dr.outputs.vpc_id
  accepter_vpc_cidr = data.terraform_remote_state.dr.outputs.vpc_cidr
  accepter_region   = var.dr_region
  accepter_route_table_ids = [
    data.terraform_remote_state.dr.outputs.public_route_table_id,
    data.terraform_remote_state.dr.outputs.private_app_route_table_id,
    data.terraform_remote_state.dr.outputs.private_data_route_table_id,
  ]

  tags = local.common_tags
}
