############################################################
# secrets module - KMS (optional) + Secrets Manager + SSM
#
# Creates the three canonical secrets defined in the spec:
#   shopcloud/db/master      - Postgres connection info
#   shopcloud/redis/auth     - Redis endpoint + auth token
#   shopcloud/cognito/config - both user pool IDs + client IDs
#
# Secret *values* are populated as placeholders here and later
# overwritten by the rds/elasticache/cognito modules with
# aws_secretsmanager_secret_version. That lets us create the
# ARNs first (External Secrets Operator references them before
# the DB exists).
############################################################

locals {
  tags = merge(var.tags, { Module = "secrets" })

  secret_prefix = var.secret_prefix
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------
# KMS customer-managed key (optional - $1/mo)
# ----------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key ? 1 : 0

  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowServiceUsage"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "secretsmanager.amazonaws.com",
        "rds.amazonaws.com",
        "elasticache.amazonaws.com",
        "logs.${data.aws_region.current.region}.amazonaws.com",
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "main" {
  count = var.create_kms_key ? 1 : 0

  description             = "${var.name_prefix} customer-managed key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-kms"
  })
}

resource "aws_kms_alias" "main" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.main[0].key_id
}

locals {
  kms_key_id  = var.create_kms_key ? aws_kms_key.main[0].key_id : null
  kms_key_arn = var.create_kms_key ? aws_kms_key.main[0].arn : null
}

# ----------------------------------------------------------
# Random bootstrap password (only for initial placeholder).
# The rds module overwrites this with the real DB password.
# ----------------------------------------------------------

resource "random_password" "db_bootstrap" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+[]{}"
}

resource "random_password" "redis_auth_bootstrap" {
  length  = 32
  special = false
}

# ----------------------------------------------------------
# Secret definitions
# ----------------------------------------------------------

resource "aws_secretsmanager_secret" "db_master" {
  name                    = "${local.secret_prefix}/db/master"
  description             = "Postgres master credentials + connection info"
  kms_key_id              = local.kms_key_id
  recovery_window_in_days = 7

  dynamic "replica" {
    for_each = var.replica_region != null && var.replica_region != "" ? [1] : []
    content {
      region = var.replica_region
    }
  }

  tags = merge(local.tags, { Name = "${local.secret_prefix}/db/master" })
}

resource "aws_secretsmanager_secret_version" "db_master_initial" {
  secret_id = aws_secretsmanager_secret.db_master.id
  secret_string = jsonencode({
    username = "shopcloud_admin"
    password = random_password.db_bootstrap.result
    engine   = "postgres"
    host     = "pending"
    port     = 5432
    dbname   = "shopcloud"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "${local.secret_prefix}/redis/auth"
  description             = "Redis endpoint + auth token"
  kms_key_id              = local.kms_key_id
  recovery_window_in_days = 7

  dynamic "replica" {
    for_each = var.replica_region != null && var.replica_region != "" ? [1] : []
    content {
      region = var.replica_region
    }
  }

  tags = merge(local.tags, { Name = "${local.secret_prefix}/redis/auth" })
}

resource "aws_secretsmanager_secret_version" "redis_auth_initial" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth_bootstrap.result
    endpoint   = "pending"
    port       = 6379
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "cognito_config" {
  name                    = "${local.secret_prefix}/cognito/config"
  description             = "Customer + admin user pool + client IDs"
  kms_key_id              = local.kms_key_id
  recovery_window_in_days = 7

  dynamic "replica" {
    for_each = var.replica_region != null && var.replica_region != "" ? [1] : []
    content {
      region = var.replica_region
    }
  }

  tags = merge(local.tags, { Name = "${local.secret_prefix}/cognito/config" })
}

resource "aws_secretsmanager_secret_version" "cognito_config_initial" {
  secret_id = aws_secretsmanager_secret.cognito_config.id
  secret_string = jsonencode({
    customer_pool_id = "pending"
    customer_client  = "pending"
    admin_pool_id    = "pending"
    admin_client     = "pending"
    region           = data.aws_region.current.region
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ----------------------------------------------------------
# SSM Parameter Store - non-sensitive config (free, String type)
# ----------------------------------------------------------

resource "aws_ssm_parameter" "environment" {
  name  = "/${local.secret_prefix}/config/environment"
  type  = "String"
  value = "production"
  tier  = "Standard"
  tags  = local.tags
}

resource "aws_ssm_parameter" "log_level" {
  name  = "/${local.secret_prefix}/config/log_level"
  type  = "String"
  value = "info"
  tier  = "Standard"
  tags  = local.tags
}
