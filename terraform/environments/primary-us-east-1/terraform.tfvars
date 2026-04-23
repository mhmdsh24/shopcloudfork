############################################################
# Primary region (us-east-1) variable values.
# Every value below is also the module default — this file
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
# GitHub OIDC — deploy role trust policy.
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
# Phase 4 toggles — keep OFF for the first apply. Flip them
# on after the public ALB exists (post kubectl apply).
############################################################

enable_cloudfront = false
enable_vpn        = false
enable_cloudtrail = true
