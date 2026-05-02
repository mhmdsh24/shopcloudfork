variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "domain_name" {
  description = "Apex domain. CloudFront will serve app.<domain>."
  type        = string
}

variable "alb_dns_name" {
  description = "CloudFront origin DNS name. Use the primary ALB DNS name for single-origin mode, or origin.<domain> when Route 53 latency records choose the regional ALB."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 public zone ID to place ACM validation records in. Leave empty to use the default *.cloudfront.net hostname without a custom domain or ACM cert."
  type        = string
  default     = ""
}

variable "rate_limit_per_5min" {
  description = "Per-IP rate limit over a 5-minute window."
  type        = number
  default     = 2000
}

variable "tags" {
  type    = map(string)
  default = {}
}
