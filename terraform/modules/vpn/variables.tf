variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "client_cidr" {
  description = "CIDR block to assign to VPN clients."
  type        = string
  default     = "10.0.100.0/22"
}

variable "subnet_id" {
  description = "Single private subnet to associate the VPN with (cost-optimized)."
  type        = string
}

variable "vpc_security_group_ids" {
  description = "SG IDs to attach to the VPN endpoint."
  type        = list(string)
}

variable "authorized_cidrs" {
  description = "CIDRs VPN clients are allowed to reach (typically the private app subnet range)."
  type        = list(string)
  default     = ["10.0.10.0/23"]
}

variable "server_certificate_arn" {
  description = "ACM cert ARN for the VPN server."
  type        = string
}

variable "client_root_certificate_arn" {
  description = "ACM cert ARN for the client root (mutual TLS)."
  type        = string
}

variable "dns_servers" {
  description = "DNS servers advertised to clients. Defaults to VPC resolver."
  type        = list(string)
  default     = ["10.0.0.2"]
}

variable "log_group_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
