############################################################
# DR environment (eu-west-1) - inputs
############################################################

variable "project_name" {
  description = "Project slug used to prefix resource names."
  type        = string
  default     = "shopcloud"
}

variable "environment" {
  description = "Logical environment label."
  type        = string
  default     = "production"
}

variable "dr_region" {
  description = "DR AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "primary_region" {
  description = "Primary AWS region used by shared regional services such as Cognito and the invoice queue."
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Exactly two AZs in the DR region."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR for the DR region (must not overlap primary)."
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private app subnet CIDRs."
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "Private data subnet CIDRs (RDS replica, ElastiCache)."
  type        = list(string)
  default     = ["10.1.20.0/24", "10.1.21.0/24"]
}

variable "vpn_client_cidr" {
  description = "Client VPN CIDR (same range as primary; VPN itself is in primary only)."
  type        = string
  default     = "10.0.100.0/22"
}

variable "eks_cluster_name" {
  description = "DR EKS cluster name used for subnet tagging and IRSA role names."
  type        = string
  default     = "shopcloud-dr"
}

variable "enable_interface_endpoints" {
  description = "Set true to enable paid ECR/STS interface VPC endpoints."
  type        = bool
  default     = false
}

############################################################
# Phase 2 - Data layer
############################################################

variable "postgres_instance_class" {
  description = "RDS replica instance class. db.t3.micro matches primary for free tier."
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_multi_az" {
  description = "Enable Multi-AZ for the DR replica. Usually false to save cost."
  type        = bool
  default     = false
}

variable "enable_dr_replica" {
  description = "Create the cross-region RDS read replica. Requires the primary env to already exist AND to have been applied with enable_cross_region_replica = true."
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache standby node type."
  type        = string
  default     = "cache.t4g.micro"
}

############################################################
# Phase 3 - DR compute layer
############################################################

variable "enable_dr_compute" {
  description = "Create the warm DR EKS compute layer and IRSA roles."
  type        = bool
  default     = true
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the DR EKS cluster."
  type        = string
  default     = "1.35"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to call the DR EKS public endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_node_instance_types" {
  description = "Instance types for the DR EKS node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "eks_node_capacity_type" {
  description = "SPOT or ON_DEMAND."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_node_desired_size" {
  type    = number
  default = 2
}

variable "eks_node_min_size" {
  type    = number
  default = 2
}

variable "eks_node_max_size" {
  type    = number
  default = 4
}
