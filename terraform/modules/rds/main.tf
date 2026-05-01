############################################################
# rds - Standard RDS PostgreSQL module (spec Option A).
#
# Three roles:
#   standalone : single-region PostgreSQL instance (no DR).
#   primary    : PostgreSQL instance that SOURCES a
#                cross-region read replica (architecturally
#                identical to `standalone` on the AWS side -
#                the distinction exists only so the DR env
#                knows it can target this instance's ARN).
#   replica    : cross-region read replica of a primary
#                instance. Inherits engine, credentials,
#                parameter group, and initial data from the
#                source. Promote with `aws rds promote-read-replica`
#                on failover.
############################################################

locals {
  tags = merge(var.tags, { Module = "rds" })

  is_replica    = var.role == "replica"
  is_primary    = var.role == "primary"
  is_standalone = var.role == "standalone"

  # "Writer" = anything that owns master credentials + creates the
  # initial database. Only non-replica clusters qualify.
  is_writer = local.is_primary || local.is_standalone
}

############################################################
# Subnet group
############################################################

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-postgres"
  description = "${var.name_prefix} Postgres subnet group"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.name_prefix}-postgres-subnets" })
}

############################################################
# Parameter group - only the writer owns one.
# Replicas inherit the source's parameter group.
############################################################

resource "aws_db_parameter_group" "this" {
  count = local.is_writer ? 1 : 0

  name        = "${var.name_prefix}-postgres"
  family      = var.parameter_group_family
  description = "${var.name_prefix} Postgres params (SSL required)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.tags
}

############################################################
# DB instance
############################################################

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-postgres"
  instance_class = var.instance_class

  # --- Writer-only fields (replica inherits from source) ---
  engine         = local.is_writer ? "postgres" : null
  engine_version = local.is_writer ? var.engine_version : null

  allocated_storage     = local.is_writer ? var.allocated_storage_gb : null
  max_allocated_storage = local.is_writer ? var.max_allocated_storage_gb : null

  db_name  = local.is_writer ? var.database_name : null
  username = local.is_writer ? var.master_username : null
  password = local.is_writer ? var.master_password : null

  parameter_group_name = local.is_writer ? aws_db_parameter_group.this[0].name : null

  # Backups only run on the writer. RDS rejects nonzero
  # retention on a read replica.
  backup_retention_period = local.is_writer ? var.backup_retention_days : 0
  backup_window           = local.is_writer ? var.preferred_backup_window : null

  # --- Replica-only field ---
  replicate_source_db = local.is_replica ? var.source_db_arn : null

  # --- Common fields ---
  storage_type      = var.storage_type
  storage_encrypted = true
  kms_key_id        = var.kms_key_id

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids

  multi_az                   = var.multi_az
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  iam_database_authentication_enabled = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null

  maintenance_window = var.preferred_maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = (local.is_writer && !var.skip_final_snapshot) ? "${var.name_prefix}-postgres-final-${formatdate("YYYYMMDDhhmmss", timestamp())}" : null

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(local.tags, { Name = "${var.name_prefix}-postgres", Role = var.role })

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      password,
    ]
  }
}

############################################################
# After the writer is up, overwrite the bootstrap DB secret
# with the real connection info. Replicas never touch the
# secret - the primary region owns it (replicated via the
# secrets module).
############################################################

resource "aws_secretsmanager_secret_version" "db_final" {
  count = local.is_writer ? 1 : 0

  secret_id = var.db_secret_id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.database_name
  })
}
