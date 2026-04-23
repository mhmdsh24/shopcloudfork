############################################################
# DR outputs — consumed by terraform/global for VPC peering
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

# ---------- Phase 2 — Data layer (DR) ----------

output "aurora_dr_endpoint" {
  value = module.rds_dr.endpoint
}

output "aurora_dr_cluster_arn" {
  value = module.rds_dr.cluster_arn
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

# ---------- Phase 5 — DR ----------

output "dr_alb_dns_name" {
  value = module.dr.alb_dns_name
}

output "dr_alb_zone_id" {
  value = module.dr.alb_zone_id
}

output "dr_alb_arn" {
  value = module.dr.alb_arn
}

output "dr_ecs_cluster_name" {
  value = module.dr.ecs_cluster_name
}

output "dr_waf_web_acl_arn" {
  value = module.dr.waf_web_acl_arn
}

output "dr_certificate_validation_records" {
  description = "Add these to Route 53 public zone (in primary) to validate the DR ALB cert."
  value = try([
    for dvo in aws_acm_certificate.dr_alb[0].domain_validation_options : {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  ], [])
}
