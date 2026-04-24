variable "domain_name" {
  description = "Apex domain (e.g. shopcloud.com)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID that the private hosted zone should be associated with."
  type        = string
}

variable "primary_alb_dns_name" {
  description = "Public ALB DNS name in the primary region (health-check target and failover primary)."
  type        = string
  default     = ""
}

variable "primary_alb_zone_id" {
  description = "Alias zone ID for the primary ALB."
  type        = string
  default     = ""
}

variable "dr_alb_dns_name" {
  description = "Public ALB DNS name in the DR region."
  type        = string
  default     = ""
}

variable "dr_alb_zone_id" {
  description = "Alias zone ID for the DR ALB."
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary region for latency routing."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Secondary region for latency routing."
  type        = string
  default     = "eu-west-1"
}

variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain (if fronting the primary)."
  type        = string
  default     = ""
}

variable "cloudfront_zone_id" {
  description = "CloudFront hosted zone ID (always Z2FDTNDATAQYW2)."
  type        = string
  default     = "Z2FDTNDATAQYW2"
}

variable "internal_alb_dns_name" {
  description = "Internal ALB DNS (for admin.internal)."
  type        = string
  default     = ""
}

variable "internal_alb_zone_id" {
  description = "Internal ALB alias zone ID."
  type        = string
  default     = ""
}

variable "ses_verification_token" {
  description = "SES domain verification token (TXT record)."
  type        = string
  default     = ""
}

variable "ses_dkim_tokens" {
  description = "Three DKIM tokens from SES."
  type        = list(string)
  default     = []
}

variable "enable_ses_records" {
  description = "Create the SES verification + DKIM Route 53 records. Static boolean so the count is knowable at plan time."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
