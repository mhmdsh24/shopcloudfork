variable "name_prefix" {
  description = "Prefix for IAM role names."
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub Actions OIDC provider. AWS allows only one per issuer URL per account, so when multiple environments share an account, exactly one of them should create it (default true) and the rest should set this false to look up the existing one instead."
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization / user that owns the repo."
  type        = string
  default     = "your-github-org"
}

variable "github_repo" {
  description = "GitHub repo name used in the OIDC sub claim."
  type        = string
  default     = "shopcloudfork"
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding Terraform state - deploy role needs read/write here."
  type        = string
}

variable "terraform_lock_table" {
  description = "DynamoDB table holding Terraform state locks."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the deploy role is allowed to push to."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
