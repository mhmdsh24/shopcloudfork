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
# Domain + email.
############################################################

domain_name = "shopcloud.com"
alert_email = ""

############################################################
# Phase 4 toggles
############################################################

enable_domain     = true
enable_cloudfront = true
enable_vpn        = true
enable_cloudtrail = false
vpn_mfa_saml_provider_arn = "arn:aws:iam::781863099565:saml-provider/shopcloud-vpn-mfa"

############################################################
# RDS PostgreSQL
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
# EKS node group sizing
############################################################

eks_node_instance_types = ["t3.medium"]
eks_node_capacity_type  = "ON_DEMAND"
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4
