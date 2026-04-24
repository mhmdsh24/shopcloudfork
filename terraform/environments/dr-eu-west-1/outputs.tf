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

output "redis_dr_endpoint" {
  value = module.redis_dr.primary_endpoint
}

output "invoices_replica_bucket_arn" {
  value = module.s3_invoices_replica.bucket_arn
}

output "invoices_replica_bucket_id" {
  value = module.s3_invoices_replica.bucket_id
}

