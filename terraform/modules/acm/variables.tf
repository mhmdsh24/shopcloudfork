variable "name" {
  description = "Friendly name for tagging (e.g. shopcloud-public-alb)."
  type        = string
}

variable "domain_name" {
  description = "Primary FQDN for the cert."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional SANs."
  type        = list(string)
  default     = []
}

variable "route53_zone_id" {
  description = "Public hosted zone where DNS-01 validation records go."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
