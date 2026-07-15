############################################################
# Phase 3 - Compute
#   * iam          : GitHub OIDC deploy role
#   * cognito      : customer + admin pools
#   * sqs-lambda   : SQS + Lambda + SES
#   * eks          : cluster + spot nodes + IRSA roles
############################################################

# ----------------------------------------------------------
# IAM - GitHub deploy role (depends on ECR repo ARNs)
# ----------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  name_prefix            = local.name_prefix
  github_org             = var.github_org
  github_repo            = var.github_repo
  terraform_state_bucket = "shopcloud-tfstate-${data.aws_caller_identity.current.account_id}"
  terraform_lock_table   = "shopcloud-terraform-locks"
  ecr_repository_arns    = values(module.ecr.repository_arns)

  tags = local.common_tags
}

# ----------------------------------------------------------
# Cognito - populates the cognito_config secret once pools exist
# ----------------------------------------------------------
module "cognito" {
  source = "../../modules/cognito"

  name_prefix              = local.name_prefix
  cognito_config_secret_id = module.secrets.cognito_secret_arn
  callback_urls            = ["https://${var.domain_name}/auth/callback"]
  logout_urls              = ["https://${var.domain_name}/auth/logout"]
  admin_callback_urls      = ["https://admin.internal.${var.domain_name}/auth/callback"]
  admin_logout_urls        = ["https://admin.internal.${var.domain_name}/auth/logout"]

  tags = local.common_tags

  # Ensure the bootstrap `pending` secret version exists before Cognito writes
  # the final pool/client IDs, so AWSCURRENT ends on the real config.
  depends_on = [module.secrets]
}

# ----------------------------------------------------------
# SQS / Lambda / SES
# ----------------------------------------------------------
module "sqs_lambda" {
  source = "../../modules/sqs-lambda"

  name_prefix        = local.name_prefix
  invoice_bucket_id  = module.s3_invoices.bucket_id
  invoice_bucket_arn = module.s3_invoices.bucket_arn
  ses_domain         = var.domain_name
  ses_from_address   = var.invoice_sender_email != "" ? var.invoice_sender_email : "invoices@${var.domain_name}"

  tags = local.common_tags
}

# ----------------------------------------------------------
# EKS - cluster + IRSA for every service account we need
# ----------------------------------------------------------

locals {
  # Compact IAM policies for each IRSA role.
  irsa_policies = {
    catalog = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["rds-db:connect"]
          Resource = "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds.db_resource_id}/shopcloud_catalog"
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = module.secrets.db_secret_arn
        },
      ]
    })

    cart = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = module.secrets.redis_secret_arn
        },
      ]
    })

    checkout = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["rds-db:connect"]
          Resource = "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds.db_resource_id}/shopcloud_checkout"
        },
        {
          Effect   = "Allow"
          Action   = ["sqs:SendMessage"]
          Resource = module.sqs_lambda.invoice_queue_arn
        },
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = [
            module.secrets.db_secret_arn,
            module.secrets.redis_secret_arn,
          ]
        },
      ]
    })

    auth = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "cognito-idp:AdminInitiateAuth",
            "cognito-idp:AdminConfirmSignUp",
            "cognito-idp:AdminCreateUser",
            "cognito-idp:AdminGetUser",
            "cognito-idp:AdminSetUserPassword",
            "cognito-idp:AdminUpdateUserAttributes",
            "cognito-idp:ListUsers",
          ]
          Resource = [module.cognito.customer_pool_arn, module.cognito.admin_pool_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = module.secrets.cognito_secret_arn
        },
      ]
    })

    admin = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "rds-db:connect",
          ]
          Resource = "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${module.rds.db_resource_id}/shopcloud_admin"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket",
          ]
          Resource = [
            module.s3_invoices.bucket_arn,
            "${module.s3_invoices.bucket_arn}/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = module.secrets.db_secret_arn
        },
      ]
    })

    external-secrets = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
            "secretsmanager:ListSecrets",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
          ]
          Resource = module.secrets.kms_key_arn
        },
        {
          Effect   = "Allow"
          Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
          Resource = "arn:aws:ssm:${var.primary_region}:${data.aws_caller_identity.current.account_id}:parameter/shopcloud/*"
        },
      ]
    })

    aws-lb-controller = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["iam:CreateServiceLinkedRole"]
          Resource = "*"
          Condition = {
            StringEquals = {
              "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
            }
          }
        },
        {
          Effect = "Allow"
          Action = [
            "ec2:DescribeAccountAttributes",
            "ec2:DescribeAddresses",
            "ec2:DescribeAvailabilityZones",
            "ec2:DescribeInternetGateways",
            "ec2:DescribeVpcs",
            "ec2:DescribeVpcPeeringConnections",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeInstances",
            "ec2:DescribeNetworkInterfaces",
            "ec2:DescribeTags",
            "ec2:GetCoipPoolUsage",
            "ec2:DescribeCoipPools",
            "elasticloadbalancing:DescribeLoadBalancers",
            "elasticloadbalancing:DescribeLoadBalancerAttributes",
            "elasticloadbalancing:DescribeListeners",
            "elasticloadbalancing:DescribeListenerCertificates",
            "elasticloadbalancing:DescribeSSLPolicies",
            "elasticloadbalancing:DescribeRules",
            "elasticloadbalancing:DescribeTargetGroups",
            "elasticloadbalancing:DescribeTargetGroupAttributes",
            "elasticloadbalancing:DescribeTargetHealth",
            "elasticloadbalancing:DescribeTags",
            "cognito-idp:DescribeUserPoolClient",
            "acm:ListCertificates",
            "acm:DescribeCertificate",
            "iam:ListServerCertificates",
            "iam:GetServerCertificate",
            "waf-regional:GetWebACL",
            "wafv2:GetWebACL",
            "wafv2:GetWebACLForResource",
            "wafv2:AssociateWebACL",
            "wafv2:DisassociateWebACL",
            "shield:GetSubscriptionState",
            "shield:DescribeProtection",
            "shield:CreateProtection",
            "shield:DeleteProtection",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:RevokeSecurityGroupIngress",
            "ec2:CreateSecurityGroup",
            "ec2:CreateTags",
            "ec2:DeleteTags",
            "ec2:DeleteSecurityGroup",
            "elasticloadbalancing:CreateLoadBalancer",
            "elasticloadbalancing:CreateTargetGroup",
            "elasticloadbalancing:CreateListener",
            "elasticloadbalancing:DeleteListener",
            "elasticloadbalancing:CreateRule",
            "elasticloadbalancing:DeleteRule",
            "elasticloadbalancing:SetWebAcl",
            "elasticloadbalancing:ModifyListener",
            "elasticloadbalancing:AddListenerCertificates",
            "elasticloadbalancing:RemoveListenerCertificates",
            "elasticloadbalancing:ModifyRule",
            "elasticloadbalancing:AddTags",
            "elasticloadbalancing:RemoveTags",
            "elasticloadbalancing:SetIpAddressType",
            "elasticloadbalancing:SetSecurityGroups",
            "elasticloadbalancing:SetSubnets",
            "elasticloadbalancing:DeleteLoadBalancer",
            "elasticloadbalancing:ModifyTargetGroup",
            "elasticloadbalancing:ModifyTargetGroupAttributes",
            "elasticloadbalancing:DeleteTargetGroup",
            "elasticloadbalancing:RegisterTargets",
            "elasticloadbalancing:DeregisterTargets",
          ]
          Resource = "*"
        },
      ]
    })

    cluster-autoscaler = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities",
            "autoscaling:DescribeTags",
            "ec2:DescribeInstanceTypes",
            "ec2:DescribeLaunchTemplateVersions",
            "eks:DescribeNodegroup",
          ]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup",
          ]
          Resource = "*"
        },
      ]
    })

    keda = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "sqs:GetQueueAttributes",
            "sqs:GetQueueUrl",
            "sqs:ListQueues",
          ]
          Resource = "*"
        },
      ]
    })
  }
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.eks_cluster_name
  kubernetes_version = var.eks_cluster_version

  subnet_ids              = module.networking.private_app_subnet_ids
  node_security_group_ids = [module.networking.security_group_ids.eks_nodes]

  public_access_cidrs = var.eks_public_access_cidrs

  node_instance_types = var.eks_node_instance_types
  node_capacity_type  = var.eks_node_capacity_type
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size

  kms_key_arn = module.secrets.kms_key_arn

  cluster_admin_iam_arns = [module.iam.github_deploy_role_arn]

  irsa_service_accounts = {
    catalog = {
      namespace       = "shopcloud"
      service_account = "catalog"
      policy_json     = local.irsa_policies.catalog
    }
    cart = {
      namespace       = "shopcloud"
      service_account = "cart"
      policy_json     = local.irsa_policies.cart
    }
    checkout = {
      namespace       = "shopcloud"
      service_account = "checkout"
      policy_json     = local.irsa_policies.checkout
    }
    auth = {
      namespace       = "shopcloud"
      service_account = "auth"
      policy_json     = local.irsa_policies.auth
    }
    admin = {
      namespace       = "shopcloud"
      service_account = "admin"
      policy_json     = local.irsa_policies.admin
    }
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_json     = local.irsa_policies.external-secrets
    }
    aws-lb-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy_json     = local.irsa_policies.aws-lb-controller
    }
    cluster-autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
      policy_json     = local.irsa_policies.cluster-autoscaler
    }
    keda = {
      namespace       = "keda"
      service_account = "keda-operator"
      policy_json     = local.irsa_policies.keda
    }
  }

  tags = local.common_tags
}
