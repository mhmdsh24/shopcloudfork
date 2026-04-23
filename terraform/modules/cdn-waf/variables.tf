variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "domain_name" {
  description = "Apex domain. CloudFront will serve app.<domain>."
  type        = string
}

variable "alb_dns_name" {
  description = "Origin ALB DNS name."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 public zone ID to place ACM validation records in."
  type        = string
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
