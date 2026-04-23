############################################################
# Outputs - consumed by other environments (DR, global)
# via terraform_remote_state.
############################################################

output "aws_account_id" {
  description = "AWS account ID of the primary region."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

# ---------- Networking ----------

output "vpc_id" {
  value = module.networking.vpc_id
}

output "vpc_cidr" {
  value = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.networking.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  value = module.networking.private_data_subnet_ids
}

output "public_route_table_id" {
  value = module.networking.public_route_table_id
}

output "private_app_route_table_id" {
  value = module.networking.private_app_route_table_id
}

output "private_data_route_table_id" {
  value = module.networking.private_data_route_table_id
}

output "security_group_ids" {
  value = module.networking.security_group_ids
}

output "availability_zones" {
  value = module.networking.availability_zones
}

# ---------- Phase 2 - Data layer ----------

output "kms_key_arn" {
  value = module.secrets.kms_key_arn
}

output "db_secret_arn" {
  value = module.secrets.db_secret_arn
}

output "redis_secret_arn" {
  value = module.secrets.redis_secret_arn
}

output "cognito_secret_arn" {
  value = module.secrets.cognito_secret_arn
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "postgres_endpoint" {
  description = "RDS PostgreSQL endpoint in host:port form."
  value       = module.rds.endpoint
}

output "postgres_address" {
  description = "RDS PostgreSQL hostname only."
  value       = module.rds.address
}

output "postgres_port" {
  value = module.rds.port
}

output "postgres_db_instance_id" {
  description = "RDS DB instance identifier."
  value       = module.rds.db_instance_id
}

output "postgres_db_instance_arn" {
  description = "RDS DB instance ARN. Feed this into the DR region as source_db_arn to build a cross-region read replica."
  value       = module.rds.db_instance_arn
}

output "postgres_db_resource_id" {
  description = "DBI resource ID (dbi-...). Use when constructing IAM DB-auth ARNs."
  value       = module.rds.db_resource_id
}

output "redis_primary_endpoint" {
  value = module.redis.primary_endpoint
}

output "invoices_bucket_arn" {
  value = module.s3_invoices.bucket_arn
}

output "invoices_bucket_id" {
  value = module.s3_invoices.bucket_id
}

# ---------- Phase 3 - Compute ----------

output "github_deploy_role_arn" {
  value = module.iam.github_deploy_role_arn
}

output "cognito_customer_pool_id" {
  value = module.cognito.customer_pool_id
}

output "cognito_customer_client_id" {
  value = module.cognito.customer_client_id
}

output "cognito_admin_pool_id" {
  value = module.cognito.admin_pool_id
}

output "cognito_admin_client_id" {
  value = module.cognito.admin_client_id
}

output "event_bus_name" {
  value = module.sqs_lambda.event_bus_name
}

output "invoice_queue_url" {
  value = module.sqs_lambda.invoice_queue_url
}

output "invoice_queue_arn" {
  value = module.sqs_lambda.invoice_queue_arn
}

output "invoice_lambda_arn" {
  value = module.sqs_lambda.lambda_function_arn
}

output "ses_domain_verification_token" {
  description = "Add as _amazonses TXT record in Route 53."
  value       = module.sqs_lambda.ses_domain_verification_token
}

output "ses_dkim_tokens" {
  description = "Add as three _domainkey CNAMEs."
  value       = module.sqs_lambda.ses_dkim_tokens
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "eks_irsa_role_arns" {
  value = module.eks.irsa_role_arns
}

# ---------- Phase 4 - Edge & Access ----------
# Every output below is nullable: `null` when enable_domain = false.

output "public_zone_id" {
  value = try(module.dns[0].public_zone_id, null)
}

output "public_zone_name_servers" {
  description = "Configure these at your domain registrar."
  value       = try(module.dns[0].public_zone_name_servers, null)
}

output "private_zone_id" {
  value = try(module.dns[0].private_zone_id, null)
}

output "cloudfront_domain_name" {
  value = try(module.cdn_waf[0].distribution_domain_name, null)
}

output "cloudfront_distribution_id" {
  value = try(module.cdn_waf[0].distribution_id, null)
}

output "cloudfront_waf_acl_arn" {
  value = try(module.cdn_waf[0].web_acl_arn, null)
}

output "cloudfront_certificate_arn" {
  value = try(module.cdn_waf[0].certificate_arn, null)
}

output "public_alb_certificate_arn" {
  description = "ACM cert ARN to set on the public ALB ingress annotation. Null when enable_domain = false."
  value       = try(module.acm_public_alb[0].certificate_arn, null)
}

output "internal_alb_certificate_arn" {
  description = "ACM cert ARN to set on the internal ALB ingress annotation. Null when enable_domain = false."
  value       = try(module.acm_internal_alb[0].certificate_arn, null)
}

output "vpn_endpoint_id" {
  value = try(module.vpn[0].endpoint_id, null)
}

output "vpn_dns_name" {
  value = try(module.vpn[0].dns_name, null)
}

# ---------- Phase 6 - Monitoring ----------

output "alerts_sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "cloudtrail_arn" {
  value = module.monitoring.cloudtrail_arn
}
