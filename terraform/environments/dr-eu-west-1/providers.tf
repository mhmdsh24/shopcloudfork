provider "aws" {
  region = var.dr_region

  default_tags {
    tags = local.common_tags
  }
}
