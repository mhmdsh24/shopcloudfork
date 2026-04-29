############################################################
# DR outputs - consumed by terraform/global for VPC peering
# and later by phases that deploy DR resources.
############################################################

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  value = var.dr_region
}

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

# ---------- Phase 2 - Data layer (DR) ----------

output "postgres_dr_replica_endpoint" {
  description = "Cross-region RDS read-replica endpoint. Null when enable_dr_replica = false."
  value       = try(module.rds_dr[0].endpoint, null)
}

output "postgres_dr_replica_arn" {
  description = "Cross-region RDS read-replica ARN. Null when enable_dr_replica = false."
  value       = try(module.rds_dr[0].db_instance_arn, null)
}

output "postgres_dr_replica_id" {
  description = "Cross-region RDS read-replica identifier. Null when enable_dr_replica = false."
  value       = try(module.rds_dr[0].db_instance_id, null)
}

output "postgres_dr_replica_resource_id" {
  description = "DBI resource ID for IAM DB auth against the DR read replica. Null when enable_dr_replica = false."
  value       = try(module.rds_dr[0].db_resource_id, null)
}

output "redis_dr_endpoint" {
  value = module.redis_dr.primary_endpoint
}

output "invoices_replica_bucket_arn" {
  value = module.s3_invoices_replica.bucket_arn
}

output "invoices_replica_bucket_id" {
  value = module.s3_invoices_replica.bucket_id
}

output "dr_db_secret_arn" {
  value = aws_secretsmanager_secret.db_reader.arn
}

output "dr_redis_secret_arn" {
  value = aws_secretsmanager_secret.redis_dr.arn
}

# ---------- Phase 3 - DR compute layer ----------

output "eks_cluster_name" {
  value = try(module.eks_dr[0].cluster_name, null)
}

output "eks_cluster_endpoint" {
  value = try(module.eks_dr[0].cluster_endpoint, null)
}

output "eks_oidc_provider_arn" {
  value = try(module.eks_dr[0].oidc_provider_arn, null)
}

output "eks_irsa_role_arns" {
  value = try(module.eks_dr[0].irsa_role_arns, null)
}
