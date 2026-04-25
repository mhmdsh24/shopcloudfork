############################################################
# Primary region (us-east-1) variable values.
# Every value below is also the module default - this file
# exists to make the active values explicit and to give you
# one place to tune before `terraform apply`.
############################################################

project_name = "shopcloud"
environment  = "production"

primary_region     = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b"]

vpc_cidr                  = "10.0.0.0/16"
public_subnet_cidrs       = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]
vpn_client_cidr           = "10.0.100.0/22"

eks_cluster_name = "shopcloud-primary"

# Cost control: interface endpoints ($7.50/mo each) are off by default.
enable_interface_endpoints = false

############################################################
# GitHub OIDC - deploy role trust policy.
# For a personal account, github_org is your GitHub username.
# github_repo must match the name you give the repo on GitHub.
############################################################

github_org  = "kamelsoubra"
github_repo = "shopcloud"

############################################################
# Domain + email. Put a real domain here once you own one in
# Route 53 (or a subdomain you delegate); put your email for
# SNS alerts to reach you.
############################################################

domain_name = "shopcloud.com"
alert_email = ""

############################################################
# Phase 4 toggles - keep OFF until you own a real domain and
# delegate its NS records to Route 53. When enable_domain = false,
# the following are skipped:
#   * Route 53 public + private hosted zones
#   * SES DKIM/SPF/DMARC records
#   * Regional ACM certs for public + internal ALB
#   * CloudFront custom alias + its ACM cert
# ALBs still work - they use the default *.elb.amazonaws.com
# hostnames over plain HTTP.
############################################################

enable_domain     = false
enable_cloudfront = false
enable_vpn        = true
enable_cloudtrail = false
vpn_mfa_saml_provider_arn = "arn:aws:iam::781863099565:saml-provider/shopcloud-vpn-mfa"

############################################################
# RDS PostgreSQL - spec Option A (Free Tier).
# Free-Tier envelope: db.t3.micro, 20 GB gp2, single-AZ,
# single region. When the account is upgraded, flip:
#   postgres_multi_az             = true
#   enable_cross_region_replica   = true   (requires DR apply)
#   postgres_backup_retention_days = 7
############################################################

postgres_engine_version         = "15.10"
postgres_parameter_group_family = "postgres15"
postgres_instance_class         = "db.t3.micro"
postgres_allocated_storage_gb   = 20
postgres_storage_type           = "gp2"
postgres_multi_az               = true
postgres_backup_retention_days  = 7
enable_cross_region_replica     = true

############################################################
# EKS node group - free-tier constrained defaults.
# Your AWS free plan blocks Spot on non-free-tier instance
# types AND blocks any EC2 type outside the free-tier list.
# t3.micro is the only option on this account. At 1 GB RAM
# per node, 1 node only, it can barely run system pods +
# 1-2 tiny app pods. To run the full workload you'll need
# to upgrade the account plan and then set:
#   eks_node_instance_types = ["t3.medium", "t3a.medium"]
#   eks_node_capacity_type  = "SPOT"
#   eks_node_desired_size   = 2
#   eks_node_min_size       = 2
#   eks_node_max_size       = 4
############################################################

eks_node_instance_types = ["t3.small"]
eks_node_capacity_type  = "ON_DEMAND"
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 3
