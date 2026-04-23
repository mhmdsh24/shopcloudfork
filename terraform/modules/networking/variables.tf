############################################################
# Networking module — inputs
############################################################

variable "name_prefix" {
  description = "Prefix applied to every resource name (e.g. shopcloud-primary)."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
}

variable "availability_zones" {
  description = "List of exactly two AZ names (e.g. [\"us-east-1a\", \"us-east-1b\"])."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Provide exactly two AZs — the cost-optimized design uses 2 AZs."
  }
}

variable "public_subnet_cidrs" {
  description = "Two /24 CIDRs for the public subnets (one per AZ)."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "Two /24 CIDRs for the private app (EKS) subnets (one per AZ)."
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "Two /24 CIDRs for the private data (RDS, ElastiCache) subnets (one per AZ)."
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS cluster name that will consume these subnets (used for subnet tagging)."
  type        = string
}

variable "vpn_client_cidr" {
  description = "CIDR assigned to Client VPN users (source for internal ALB)."
  type        = string
  default     = "10.0.100.0/22"
}

variable "flow_logs_retention_days" {
  description = "CloudWatch log retention for VPC flow logs."
  type        = number
  default     = 7
}

variable "enable_interface_endpoints" {
  description = "Whether to create the (paid) interface VPC endpoints for ECR/STS. Start disabled — NAT handles it."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Base tags applied to every resource."
  type        = map(string)
  default     = {}
}
