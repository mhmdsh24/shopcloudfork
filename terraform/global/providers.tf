############################################################
# Two aliased providers - one per region. The peering module
# is configured with these aliases to drive both sides of the
# cross-region VPC peering from a single Terraform run.
############################################################

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = local.common_tags
  }
}
