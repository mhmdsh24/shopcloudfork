############################################################
# rds — Aurora PostgreSQL cluster
############################################################

locals {
  tags = merge(var.tags, { Module = "rds" })

  is_primary    = var.role == "primary"
  is_secondary  = var.role == "secondary"
  is_standalone = var.role == "standalone"

  # master credentials only apply to primary/standalone
  needs_master_creds = local.is_primary || local.is_standalone

  # global cluster is only created on primary
  creates_global_cluster = local.is_primary && var.global_cluster_id != null
}

# ----------------------------------------------------------
# Subnet group
# ----------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-aurora"
  description = "${var.name_prefix} Aurora subnet group"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.name_prefix}-aurora-subnets" })
}

# ----------------------------------------------------------
# Parameter group (SSL required)
# ----------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name_prefix}-aurora-pg"
  family      = "aurora-postgresql15"
  description = "${var.name_prefix} Aurora cluster params"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = local.tags
}

# ----------------------------------------------------------
# Global cluster (only on primary when global_cluster_id is set)
# ----------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  count = local.creates_global_cluster ? 1 : 0

  global_cluster_identifier = var.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ----------------------------------------------------------
# Cluster
# ----------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name_prefix}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = var.engine_version

  database_name   = local.needs_master_creds ? var.database_name : null
  master_username = local.needs_master_creds ? var.master_username : null
  master_password = local.needs_master_creds ? var.master_password : null

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = var.vpc_security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = var.kms_key_id

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${var.name_prefix}-aurora-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  # Join or create a global cluster.
  # For Aurora Global Database: setting global_cluster_identifier on the
  # secondary cluster is all that's required — AWS handles the cross-region
  # replication automatically. replication_source_identifier is only for
  # non-global cross-region read replicas.
  global_cluster_identifier = local.is_primary ? (
    local.creates_global_cluster ? aws_rds_global_cluster.this[0].id : null
    ) : (
    local.is_secondary ? var.global_cluster_id : null
  )

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(local.tags, { Name = "${var.name_prefix}-aurora", Role = var.role })

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      master_password,
    ]
  }
}

# ----------------------------------------------------------
# Cluster instance(s)
# ----------------------------------------------------------

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.name_prefix}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.this.name

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  auto_minor_version_upgrade = true
  publicly_accessible        = false
  monitoring_interval        = 0

  tags = merge(local.tags, { Name = "${var.name_prefix}-aurora-${count.index}" })
}

# ----------------------------------------------------------
# Overwrite the DB secret with the real connection info once
# the cluster is up. Only on primary/standalone.
# ----------------------------------------------------------

resource "aws_secretsmanager_secret_version" "db_final" {
  # local.needs_master_creds is derived from var.role — known at plan time.
  # var.db_secret_id is a computed ARN, so we don't include it in the count
  # expression (it would break plan). If secret_id is null at apply time
  # the API call fails loudly, which is the correct behavior.
  count = local.needs_master_creds ? 1 : 0

  secret_id = var.db_secret_id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    engine   = "postgres"
    host     = aws_rds_cluster.this.endpoint
    reader   = aws_rds_cluster.this.reader_endpoint
    port     = aws_rds_cluster.this.port
    dbname   = var.database_name
  })
}
