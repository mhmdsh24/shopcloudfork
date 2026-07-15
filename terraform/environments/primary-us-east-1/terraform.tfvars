############################################################
# Primary region (us-east-1) variable values.
# Every value below is also the module default - this file
# exists to make the active values explicit and to give you
# one place to tune before `terraform apply`.
# Domain-dependent features (ACM/CloudFront/VPN) enabled for shopcloud-503q.click.
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

github_org  = "mhmdsh24"
github_repo = "shopcloudfork"

############################################################
# Domain + email.
############################################################

domain_name            = "shopcloud-503q.click"
route53_public_zone_id = "Z03870742KSFCPI8PJWDC"
invoice_sender_email   = "shopcloud.eece503q@gmail.com"
alert_email            = ""

############################################################
# Phase 4 toggles
############################################################

# domain_name/route53_public_zone_id above belong to the original fork
# author's AWS account, not this one (verified: aws route53 get-hosted-zone
# on that zone ID returns AccessDenied - it exists, just not here, and
# `aws route53 list-hosted-zones` returns zero zones owned by this account).
# Leaving enable_domain/enable_cloudfront off avoids a guaranteed failure
# in the ACM DNS-validation and Route53 record steps. VPN doesn't depend
# on the domain (it's gated by its own enable_vpn flag), so it stays on.
enable_domain = false
enable_cloudfront         = false
enable_vpn                = true
enable_cloudtrail         = false
vpn_mfa_saml_provider_arn = "" # cert-only auth; set a real SAML provider ARN to add MFA

############################################################
# RDS PostgreSQL
############################################################

postgres_engine_version         = "15.18"
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

eks_cluster_version     = "1.35"
eks_node_instance_types = ["t3.small"]
eks_node_capacity_type  = "ON_DEMAND"
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4

# dr_invoice_bucket_arn = "arn:aws:s3:::shopcloud-invoices-replica-781863099565"

############################################################
# Regional public ALBs for Route 53 latency routing
############################################################

primary_alb_dns_name = "k8s-shopcloudpublic-afbeb03e50-1960809462.us-east-1.elb.amazonaws.com"
primary_alb_zone_id  = "Z35SXDOTRQ7X7K"

internal_alb_dns_name = "internal-k8s-shopcloudadmin-0a74081895-332932850.us-east-1.elb.amazonaws.com"
internal_alb_zone_id  = "Z35SXDOTRQ7X7K"

dr_alb_dns_name = "k8s-shopcloudpublic-dca989f5cd-486176209.eu-west-1.elb.amazonaws.com"
dr_alb_zone_id  = "Z32O12XQLNTSW2"

############################################################
# VPN - fill in after running the cert generation script
############################################################

vpn_server_certificate_arn      = "arn:aws:acm:us-east-1:268810572260:certificate/215760cc-324b-4bcf-9d50-63558876bb87"
vpn_client_root_certificate_arn = "arn:aws:acm:us-east-1:268810572260:certificate/67c081aa-fa29-4fc6-bb4b-b2d24d0cc6f2"
