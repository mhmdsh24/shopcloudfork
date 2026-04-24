provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

# CloudFront ACM + WAF (CLOUDFRONT scope) must live in us-east-1.
# Since primary_region already is us-east-1, this alias is effectively
# the same provider. If you ever move primary elsewhere, this alias
# keeps CloudFront pieces in the right place.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}
