############################################################
# IAM - GitHub Actions OIDC deploy role
# IRSA roles are attached by the eks module (needs the EKS
# OIDC issuer URL) - this module only sets up cross-cutting
# identities that don't depend on EKS.
############################################################

locals {
  tags = merge(var.tags, { Module = "iam" })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ----------------------------------------------------------
# GitHub OIDC provider (one per account)
# ----------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(local.tags, { Name = "github-actions-oidc" })
}

# ----------------------------------------------------------
# Deploy role - assumed by GitHub Actions for this repo
# ----------------------------------------------------------

data "aws_iam_policy_document" "github_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.name_prefix}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
  tags               = merge(local.tags, { Name = "${var.name_prefix}-github-deploy" })
}

data "aws_iam_policy_document" "github_deploy" {
  # Terraform state access
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket}",
      "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket}/*",
    ]
  }

  statement {
    sid    = "TerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.terraform_lock_table}",
    ]
  }

  # ECR push
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid    = "ECRPush"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # EKS kubeconfig
  statement {
    sid       = "EKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = ["*"]
  }

  # Broad read access for terraform plan on infra resources.
  # Tighten to specific resource ARNs in production.
  statement {
    sid    = "TerraformPlanRead"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:Get*",
      # ECR — lifecycle policy read required for terraform refresh
      "ecr:Describe*",
      "ecr:List*",
      "ecr:Get*",
      "iam:Get*",
      "iam:List*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "elasticache:Describe*",
      "elasticache:ListTagsForResource",
      "autoscaling:Describe*",
      # Cognito — GetUserPoolMfaConfig required for terraform refresh
      "cognito-idp:Describe*",
      "cognito-idp:List*",
      "cognito-idp:Get*",
      "cloudfront:Get*",
      "cloudfront:List*",
      "route53:Get*",
      "route53:List*",
      "logs:Describe*",
      "logs:List*",
      "logs:Get*",
      "wafv2:Get*",
      "wafv2:List*",
      "secretsmanager:Describe*",
      "secretsmanager:List*",
      "secretsmanager:Get*",
      # KMS — GetKeyRotationStatus required for terraform refresh
      "kms:Describe*",
      "kms:List*",
      "kms:Get*",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "sqs:Get*",
      "sqs:List*",
      "lambda:Get*",
      "lambda:List*",
      # S3 — GetReplicationConfiguration required for terraform refresh
      "s3:GetAccelerateConfiguration",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListAllMyBuckets",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetObject",
      # SSM — DescribeParameters required for terraform refresh
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:DescribeParameters",
      "ssm:ListTagsForResource",
      # SES — GetIdentityDkimAttributes required for terraform refresh
      "ses:GetIdentity*",
      "ses:ListIdentities",
      "ses:ListTagsForResource",
      "ecs:Describe*",
      "ecs:List*",
      # EKS — required for access entry management
      "eks:Describe*",
      "eks:List*",
      "eks:AccessKubernetesApi",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.name_prefix}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
