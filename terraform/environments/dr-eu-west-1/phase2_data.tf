############################################################
# Phase 2 — Data layer (DR region)
#
# Reads the primary region's outputs via remote state so it
# can:
#   * join the primary's Aurora Global Database as a secondary
#   * create the S3 invoice-replica bucket (destination for CRR)
#
# Secrets Manager replicas are created automatically by the
# primary via the replica_region argument — nothing to do here.
############################################################

data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = "shopcloud-tfstate-781863099565"
    key    = "primary-us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

# ----------------------------------------------------------
# Aurora secondary — joins the primary's Global Database
# ----------------------------------------------------------
module "rds_dr" {
  source = "../../modules/rds"

  name_prefix = local.name_prefix
  role        = "secondary"

  # Secondary joins the Global Database created by primary.
  # AWS handles cross-region replication automatically.
  global_cluster_id = data.terraform_remote_state.primary.outputs.aurora_global_cluster_id

  engine_version = var.aurora_engine_version
  instance_class = var.aurora_instance_class
  instance_count = 1

  subnet_ids             = module.networking.private_data_subnet_ids
  vpc_security_group_ids = [module.networking.security_group_ids.rds]

  deletion_protection = false
  skip_final_snapshot = true

  tags = local.common_tags
}

# ----------------------------------------------------------
# ElastiCache Redis — standalone DR node.
#
# Global Datastore requires r-family nodes (cache.r6g.large
# minimum), which is ~$130/mo. The spec calls this out and
# recommends the fallback: a standalone cache in eu-west-1
# that starts empty and warms up post-failover. Cart/session
# data loss on failover is acceptable — users re-add items.
# ----------------------------------------------------------
module "redis_dr" {
  source = "../../modules/elasticache"

  name_prefix        = "${local.name_prefix}-standby"
  node_type          = var.redis_node_type
  num_cache_clusters = 1

  subnet_ids         = module.networking.private_data_subnet_ids
  security_group_ids = [module.networking.security_group_ids.redis]

  # DR node gets its own bootstrap auth token. Real applications
  # can read the primary's secret (replicated) to sync post-failover.
  auth_token = random_password.redis_dr_auth.result

  tags = local.common_tags
}

resource "random_password" "redis_dr_auth" {
  length  = 32
  special = false
}

# ----------------------------------------------------------
# S3 invoice replica bucket — destination of CRR from primary
# ----------------------------------------------------------
module "s3_invoices_replica" {
  source = "../../modules/s3-invoices"

  bucket_name        = "shopcloud-invoices-replica-${data.aws_caller_identity.current.account_id}"
  replica_bucket_arn = ""
  expire_after_days  = 365

  tags = local.common_tags
}
