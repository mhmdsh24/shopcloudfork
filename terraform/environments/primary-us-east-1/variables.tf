############################################################
# Primary environment (us-east-1) - inputs
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

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Exactly two AZs in the primary region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR for the primary region."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Private app subnet CIDRs (EKS workers)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "Private data subnet CIDRs (RDS, ElastiCache)."
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "vpn_client_cidr" {
  description = "CIDR assigned to Client VPN clients."
  type        = string
  default     = "10.0.100.0/22"
}

variable "eks_cluster_name" {
  description = "EKS cluster name used for subnet tagging."
  type        = string
  default     = "shopcloud-primary"
}

variable "enable_interface_endpoints" {
  description = "Set true to enable paid ECR/STS interface VPC endpoints."
  type        = bool
  default     = false
}

############################################################
# Phase 2 - Data layer
############################################################

variable "dr_region" {
  description = "DR region for cross-region replication targets."
  type        = string
  default     = "eu-west-1"
}

variable "postgres_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "15.7"
}

variable "postgres_parameter_group_family" {
  description = "DB parameter group family. Must match engine_version major."
  type        = string
  default     = "postgres15"
}

variable "postgres_instance_class" {
  description = "RDS instance class. db.t3.micro = Free Tier eligible."
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_allocated_storage_gb" {
  description = "Allocated storage in GB. 20 GB is Free Tier eligible."
  type        = number
  default     = 20
}

variable "postgres_storage_type" {
  description = "Storage type. gp2 is Free Tier eligible."
  type        = string
  default     = "gp2"
}

variable "postgres_multi_az" {
  description = "Enable Multi-AZ standby. Not Free Tier eligible (doubles hourly cost)."
  type        = bool
  default     = false
}

variable "postgres_backup_retention_days" {
  description = "Backup retention in days. Free-plan accounts may cap this at 1."
  type        = number
  default     = 7
}

variable "enable_cross_region_replica" {
  description = "Mark this RDS as the source for a cross-region read replica in the DR region. Flips role from standalone to primary. The replica itself is created by the DR environment."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "dr_invoice_bucket_arn" {
  description = "DR invoice bucket ARN for S3 cross-region replication. Leave empty on first apply; fill in after DR phase 2 is applied and re-apply primary."
  type        = string
  default     = ""
}

############################################################
# Phase 3 - Compute
############################################################

variable "github_org" {
  description = "GitHub org/user for OIDC deploy role trust."
  type        = string
  default     = "your-github-org"
}

variable "github_repo" {
  description = "GitHub repo name for OIDC deploy role trust."
  type        = string
  default     = "shopcloud"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS."
  type        = string
  default     = "1.30"
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to call the EKS public endpoint. Lock down to your admin IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_node_instance_types" {
  description = "Instance types for the EKS node group. Defaults are free-tier eligible. Expand later to t3.medium/t3a.medium on an upgraded account."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "eks_node_capacity_type" {
  description = "SPOT or ON_DEMAND. Free-plan accounts reject Spot on non-free-tier types, so use ON_DEMAND with t3.micro."
  type        = string
  default     = "ON_DEMAND"
}

variable "eks_node_desired_size" {
  description = "Desired EKS worker count. Keep at 1 on t3.micro (~1 GB RAM total)."
  type        = number
  default     = 1
}

variable "eks_node_min_size" {
  type    = number
  default = 1
}

variable "eks_node_max_size" {
  type    = number
  default = 2
}

variable "domain_name" {
  description = "Apex domain for ShopCloud (used by Cognito callbacks and SES)."
  type        = string
  default     = "shopcloud.com"
}

variable "invoice_sender_email" {
  description = "Verified SES email identity used as the From address for invoice emails. Leave empty to use invoices@domain_name once the domain is verified."
  type        = string
  default     = ""
}

############################################################
# Phase 4 - Edge & Access
############################################################

variable "enable_domain" {
  description = "Master switch for every domain-dependent resource: Route 53 zones + records, ACM certificates, and the CloudFront custom alias. Keep `false` until you own a real domain and delegate its NS records to Route 53; ALBs will run over plain HTTP against their default *.elb.amazonaws.com DNS names in the meantime."
  type        = bool
  default     = false
}

variable "enable_cloudfront" {
  description = "Create the CloudFront + WAF distribution. Requires primary_alb_dns_name to be set. enable_domain is optional: without it the distribution uses the default *.cloudfront.net URL."
  type        = bool
  default     = false
}

variable "enable_vpn" {
  description = "Create the Client VPN endpoint. ~$37/mo baseline."
  type        = bool
  default     = false
}

variable "primary_alb_dns_name" {
  description = "Primary public ALB DNS name (populated after k8s ingress is applied). Used by CloudFront + Route 53."
  type        = string
  default     = ""
}

variable "primary_alb_zone_id" {
  description = "Primary public ALB alias zone ID."
  type        = string
  default     = ""
}

variable "internal_alb_dns_name" {
  description = "Internal ALB DNS name (admin)."
  type        = string
  default     = ""
}

variable "internal_alb_zone_id" {
  description = "Internal ALB alias zone ID."
  type        = string
  default     = ""
}

variable "dr_alb_dns_name" {
  description = "DR ALB DNS name (populated from DR env remote state, or pasted in)."
  type        = string
  default     = ""
}

variable "dr_alb_zone_id" {
  description = "DR ALB alias zone ID."
  type        = string
  default     = ""
}

variable "vpn_server_certificate_arn" {
  description = "ACM cert ARN for the VPN server (must exist before enable_vpn = true)."
  type        = string
  default     = ""
}

variable "vpn_client_root_certificate_arn" {
  description = "ACM cert ARN for the VPN client root (mutual TLS)."
  type        = string
  default     = ""
}

variable "vpn_mfa_saml_provider_arn" {
  description = "IAM SAML provider ARN used for explicit VPN MFA authentication."
  type        = string
  default     = ""
  # Leave empty to use certificate-only auth. Set a real SAML provider ARN to
  # layer federated MFA on top of the mutual-TLS client certificate.

}

############################################################
# Phase 6 - Monitoring
############################################################

variable "alert_email" {
  description = "Email subscribed to the alerts SNS topic. Leave empty to skip."
  type        = string
  default     = ""
}

variable "enable_cloudtrail" {
  description = "Create a multi-region CloudTrail (free for management events)."
  type        = bool
  default     = true
}
