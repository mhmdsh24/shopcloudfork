############################################################
# ElastiCache for Redis — session + shopping cart store.
# Starts as a single-node cluster on cache.t4g.micro (free tier).
# Flip num_cache_clusters to 2+ to get automatic failover and
# Multi-AZ at any time without code changes.
############################################################

locals {
  tags = merge(var.tags, { Module = "elasticache" })
}

resource "aws_elasticache_subnet_group" "this" {
  name        = "${var.name_prefix}-redis"
  description = "${var.name_prefix} Redis subnet group"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.name_prefix}-redis-subnets" })
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.name_prefix}-redis"
  family      = "redis7"
  description = "${var.name_prefix} Redis params — LRU eviction for cache-only workloads"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = local.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "${var.name_prefix} Redis replication group"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = var.security_group_ids
  parameter_group_name = aws_elasticache_parameter_group.this.name

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.auth_token
  kms_key_id                 = var.kms_key_id

  snapshot_retention_limit = var.snapshot_retention_days
  snapshot_window          = "03:00-05:00"

  apply_immediately = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-redis" })

  lifecycle {
    ignore_changes = [auth_token]
  }
}

# ----------------------------------------------------------
# Populate the Secrets Manager secret with the real endpoint
# ----------------------------------------------------------

resource "aws_secretsmanager_secret_version" "redis_final" {
  count = var.redis_secret_id != null ? 1 : 0

  secret_id = var.redis_secret_id
  secret_string = jsonencode({
    auth_token = var.auth_token
    endpoint   = aws_elasticache_replication_group.this.primary_endpoint_address
    reader     = aws_elasticache_replication_group.this.reader_endpoint_address
    port       = 6379
    tls        = true
  })
}
