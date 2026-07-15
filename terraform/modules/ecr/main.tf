############################################################
# ECR module - one repo per service + optional cross-region
# image replication.
############################################################

locals {
  tags = merge(var.tags, { Module = "ecr" })
}

data "aws_caller_identity" "current" {}

# ----------------------------------------------------------
# Repositories
# ----------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.enable_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.tags, {
    Name    = "${var.name_prefix}/${each.key}"
    Service = each.key
  })
}

# ----------------------------------------------------------
# Lifecycle policies - keep last N tagged, expire untagged
# ----------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.keep_last_n_images} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.keep_last_n_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
    ]
  })
}

# ----------------------------------------------------------
# Cross-region replication (free, you pay only for storage in target)
# ----------------------------------------------------------

resource "aws_ecr_replication_configuration" "cross_region" {
  count = var.replica_region != "" ? 1 : 0

  replication_configuration {
    rule {
      destination {
        region      = var.replica_region
        registry_id = data.aws_caller_identity.current.account_id
      }

      repository_filter {
        filter      = "shopcloud"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
