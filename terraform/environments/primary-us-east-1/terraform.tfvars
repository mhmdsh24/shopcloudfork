############################################################
# Primary region (us-east-1) variable values.
# Every value below is also the module default - this file
# exists to make the active values explicit and to give you
# one place to tune before `terraform apply`.
# Domain-dependent features (ACM/CloudFront/VPN) disabled — requires a registered domain delegated to Route 53.
# See terraform.tfvars.prod-full-spec for complete production values.
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
# Domain + email.
############################################################

domain_name = "shopcloud.com"
alert_email = ""

############################################################
# Phase 4 toggles
############################################################

enable_domain             = false
enable_cloudfront         = true
enable_vpn                = true
enable_cloudtrail         = false
vpn_mfa_saml_provider_arn = ""   # cert-only auth; set a real SAML provider ARN to add MFA

############################################################
# RDS PostgreSQL
############################################################

postgres_engine_version         = "15.10"
postgres_parameter_group_family = "postgres15"
postgres_instance_class         = "db.t3.micro"
postgres_allocated_storage_gb   = 20
postgres_storage_type           = "gp2"
postgres_multi_az               = true
# Free-tier limit; production spec is 7 days — see terraform.tfvars.prod-full-spec
postgres_backup_retention_days = 1
enable_cross_region_replica    = true

############################################################
# EKS node group sizing
############################################################

eks_node_instance_types = ["t3.small"]
eks_node_capacity_type  = "ON_DEMAND"
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4

# dr_invoice_bucket_arn = "arn:aws:s3:::shopcloud-invoices-replica-781863099565"

############################################################
# CloudFront origin (public ALB)
############################################################

primary_alb_dns_name = "k8s-shopcloudpublic-afbeb03e50-1960809462.us-east-1.elb.amazonaws.com"
primary_alb_zone_id  = "Z35SXDOTRQ7X7K"

############################################################
# VPN - fill in after running the cert generation script
############################################################

vpn_server_certificate_arn      = "arn:aws:acm:us-east-1:781863099565:certificate/1bc3e3d6-e8c0-425c-b4a8-e06f8a4bb446"
vpn_client_root_certificate_arn = "arn:aws:acm:us-east-1:781863099565:certificate/fcd44ffa-ff0e-4d53-b49e-34615ffd9c74"
