############################################################
# Phase 2 - Data layer (primary region)
#   * secrets     : KMS + Secrets Manager + SSM
#   * ecr         : 5 image repos + cross-region replication
#   * rds         : RDS PostgreSQL (source of cross-region replica)
#   * elasticache : Redis primary
#   * s3_invoices : Invoice bucket + CRR to DR
############################################################

# ----------------------------------------------------------
# Secrets (shared with DR via replication)
# ----------------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  name_prefix    = local.name_prefix
  create_kms_key = true
  replica_region = var.dr_region

  tags = local.common_tags
}

# ----------------------------------------------------------
# ECR - 5 repos, replicated to DR region
# ----------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  replica_region = var.dr_region
  tags           = local.common_tags
}

# ----------------------------------------------------------
# RDS PostgreSQL - spec Option A (free tier).
# Role = primary  when a cross-region replica is expected in DR.
# Role = standalone otherwise (no DR DB).
# Multi-AZ is a toggle; OFF by default because the standby
# doubles the hourly cost and is not Free Tier eligible.
# ----------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name_prefix = local.name_prefix
  role        = var.enable_cross_region_replica ? "primary" : "standalone"

  engine_version         = var.postgres_engine_version
  parameter_group_family = var.postgres_parameter_group_family
  instance_class         = var.postgres_instance_class
  allocated_storage_gb   = var.postgres_allocated_storage_gb
  storage_type           = var.postgres_storage_type

  database_name   = "shopcloud"
  master_username = "shopcloud_admin"
  master_password = module.secrets.db_bootstrap_password

  subnet_ids             = module.networking.private_data_subnet_ids
  vpc_security_group_ids = [module.networking.security_group_ids.rds]

  kms_key_id   = module.secrets.kms_key_arn
  db_secret_id = module.secrets.db_secret_arn

  multi_az              = var.postgres_multi_az
  backup_retention_days = var.postgres_backup_retention_days

  deletion_protection = false
  skip_final_snapshot = true

  tags = local.common_tags
}

# ----------------------------------------------------------
# ElastiCache Redis - primary
# ----------------------------------------------------------
module "redis" {
  source = "../../modules/elasticache"

  name_prefix        = local.name_prefix
  node_type          = var.redis_node_type
  num_cache_clusters = 2

  subnet_ids         = module.networking.private_data_subnet_ids
  security_group_ids = [module.networking.security_group_ids.redis]

  auth_token      = module.secrets.redis_bootstrap_auth_token
  redis_secret_id = module.secrets.redis_secret_arn
  kms_key_id      = module.secrets.kms_key_arn

  tags = local.common_tags
}

# ----------------------------------------------------------
# S3 invoices - primary bucket, replicated to DR bucket.
# The DR bucket is created in the dr environment and its ARN
# is injected via var.dr_invoice_bucket_arn (left empty until
# Phase 2 is applied in DR, at which point you set it and
# re-apply primary to enable replication).
# ----------------------------------------------------------
module "s3_invoices" {
  source = "../../modules/s3-invoices"

  bucket_name        = "shopcloud-invoices-${data.aws_caller_identity.current.account_id}"
  replica_bucket_arn = var.dr_invoice_bucket_arn
  expire_after_days  = 365

  tags = local.common_tags
}
