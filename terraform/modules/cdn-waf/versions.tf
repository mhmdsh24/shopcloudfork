terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
      # us_east_1 alias needed because CloudFront ACM + WAF (CLOUDFRONT scope)
      # must live in us-east-1 regardless of where the app runs.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
