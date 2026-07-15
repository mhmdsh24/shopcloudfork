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

  # dev-us-east-1's secrets already occupy the unprefixed "shopcloud/*"
  # names in this account (both environments live in 268810572260).
  # Without this, primary's RDS/Redis/Cognito modules would silently
  # overwrite dev's live secret values with primary's own connection
  # info the moment this environment applies.
  secret_prefix = "shopcloud-primary"

  tags = local.common_tags
}

# ----------------------------------------------------------
# ECR - 5 repos, replicated to DR region
# ----------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  # dev-us-east-1 already owns the unprefixed "shopcloud/*" repos in this
  # account. dev's own replication configuration (PREFIX_MATCH on
  # "shopcloud") already covers these shopcloud-primary/* repos too, since
  # AWS allows only one replication configuration per account - so
  # replica_region stays empty here to avoid a second, colliding one.
  name_prefix    = "shopcloud-primary"
  replica_region = ""
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

  # dev-us-east-1 already owns "shopcloud-invoices-<account-id>" in this
  # account; give primary its own bucket rather than mixing dev and
  # production invoice PDFs together.
  bucket_name        = "shopcloud-invoices-primary-${data.aws_caller_identity.current.account_id}"
  replica_bucket_arn = var.dr_invoice_bucket_arn
  expire_after_days  = 365

  tags = local.common_tags
}
