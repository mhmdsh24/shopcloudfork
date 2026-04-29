############################################################
# Phase 2 - Data layer (DR region)
#
# Reads the primary region's outputs via remote state so it
# can build:
#   * an optional cross-region RDS read replica of the
#     primary PostgreSQL instance (spec §11 Option A)
#   * a standalone ElastiCache Redis node (warm on failover)
#   * the S3 invoice-replica bucket (destination for CRR)
#
# Secrets Manager replicas are created automatically by the
# primary via the replica_region argument - nothing to do here.
############################################################

data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = "shopcloud-tfstate-781863099565"
    key    = "primary-us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

# AWS-managed RDS key in the DR region. Cross-region replicas of an
# encrypted source must specify a KMS key in the target region.
data "aws_kms_key" "rds" {
  key_id = "alias/aws/rds"
}

# ----------------------------------------------------------
# Cross-region RDS read replica.
#
# Gated behind enable_dr_replica so this env can be applied
# standalone before the primary is ready. Flip to true only
# after the primary was applied with
# `enable_cross_region_replica = true`.
# ----------------------------------------------------------
module "rds_dr" {
  count  = var.enable_dr_replica ? 1 : 0
  source = "../../modules/rds"

  name_prefix = local.name_prefix
  role        = "replica"

  # Engine / credentials / parameter group are inherited from
  # the source DB, so we pass only the replica-specific wiring.
  source_db_arn = data.terraform_remote_state.primary.outputs.postgres_db_instance_arn

  instance_class = var.postgres_instance_class
  multi_az       = var.postgres_multi_az

  subnet_ids             = module.networking.private_data_subnet_ids
  vpc_security_group_ids = [module.networking.security_group_ids.rds]

  kms_key_id = data.aws_kms_key.rds.arn

  # Replicas cannot hold backups or own the DB secret.
  backup_retention_days = 0
  deletion_protection   = false
  skip_final_snapshot   = true

  tags = local.common_tags
}

# ----------------------------------------------------------
# ElastiCache Redis - standalone DR node.
#
# Global Datastore requires r-family nodes (cache.r6g.large
# minimum, ~$130/mo), so we use the spec's documented
# fallback: a standalone cache that starts empty and warms
# up post-failover. Cart/session data loss on failover is
# acceptable - users re-add items.
# ----------------------------------------------------------
module "redis_dr" {
  source = "../../modules/elasticache"

  name_prefix        = "${local.name_prefix}-standby"
  node_type          = var.redis_node_type
  num_cache_clusters = 1

  subnet_ids         = module.networking.private_data_subnet_ids
  security_group_ids = [module.networking.security_group_ids.redis]

  # DR node gets its own bootstrap auth token. Applications
  # can read the primary's (replicated) secret to sync post-
  # failover.
  auth_token = random_password.redis_dr_auth.result

  # Primary region owns the shopcloud/redis/auth secret
  # (replicated to DR). Don't overwrite it from here.
  populate_secret = false

  tags = local.common_tags
}

resource "random_password" "redis_dr_auth" {
  length  = 32
  special = false
}

# ----------------------------------------------------------
# DR-local connection secrets for pods running in eu-west-1.
# The primary region owns the canonical secrets, which contain
# primary endpoints. These DR secrets point workloads at the
# regional read replica and standby Redis during failover or
# latency-routed operation.
# ----------------------------------------------------------

resource "aws_secretsmanager_secret" "db_reader" {
  name                    = "shopcloud/dr/db/reader"
  description             = "DR Postgres read-replica connection info"
  recovery_window_in_days = 7

  tags = merge(local.common_tags, { Name = "shopcloud/dr/db/reader" })
}

resource "aws_secretsmanager_secret_version" "db_reader" {
  count = var.enable_dr_replica ? 1 : 0

  secret_id = aws_secretsmanager_secret.db_reader.id
  secret_string = jsonencode({
    username = "shopcloud_admin"
    engine   = "postgres"
    host     = module.rds_dr[0].address
    port     = module.rds_dr[0].port
    dbname   = "shopcloud"
  })
}

resource "aws_secretsmanager_secret" "redis_dr" {
  name                    = "shopcloud/dr/redis/auth"
  description             = "DR Redis endpoint + auth token"
  recovery_window_in_days = 7

  tags = merge(local.common_tags, { Name = "shopcloud/dr/redis/auth" })
}

resource "aws_secretsmanager_secret_version" "redis_dr" {
  secret_id = aws_secretsmanager_secret.redis_dr.id
  secret_string = jsonencode({
    auth_token = random_password.redis_dr_auth.result
    endpoint   = module.redis_dr.primary_endpoint
    reader     = module.redis_dr.reader_endpoint
    port       = 6379
    tls        = true
  })
}

# ----------------------------------------------------------
# S3 invoice replica bucket - destination of CRR from primary
# ----------------------------------------------------------
module "s3_invoices_replica" {
  source = "../../modules/s3-invoices"

  bucket_name        = "shopcloud-invoices-replica-${data.aws_caller_identity.current.account_id}"
  replica_bucket_arn = ""
  expire_after_days  = 365

  tags = local.common_tags
}
