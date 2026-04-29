############################################################
# Phase 3 - DR compute layer
#   * eks : warm regional EKS cluster + IRSA roles
#
# The DR app layer uses replicated images, DR-local Redis,
# the cross-region RDS read replica, and the primary invoice
# queue/Cognito pools until a full regional cutover is needed.
############################################################

locals {
  dr_db_resource_id = try(
    module.rds_dr[0].db_resource_id,
    data.terraform_remote_state.primary.outputs.postgres_db_resource_id,
  )

  dr_db_secret_arn      = "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:shopcloud/dr/db/reader-*"
  dr_redis_secret_arn   = "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:shopcloud/dr/redis/auth-*"
  dr_cognito_secret_arn = "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:shopcloud/cognito/config-*"

  customer_pool_arn = "arn:aws:cognito-idp:${var.primary_region}:${data.aws_caller_identity.current.account_id}:userpool/${data.terraform_remote_state.primary.outputs.cognito_customer_pool_id}"
  admin_pool_arn    = "arn:aws:cognito-idp:${var.primary_region}:${data.aws_caller_identity.current.account_id}:userpool/${data.terraform_remote_state.primary.outputs.cognito_admin_pool_id}"

  dr_irsa_policies = {
    catalog = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["rds-db:connect"]
          Resource = "arn:aws:rds-db:${var.dr_region}:${data.aws_caller_identity.current.account_id}:dbuser:${local.dr_db_resource_id}/shopcloud_catalog"
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = local.dr_db_secret_arn
        },
      ]
    })

    cart = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = local.dr_redis_secret_arn
        },
      ]
    })

    checkout = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["rds-db:connect"]
          Resource = "arn:aws:rds-db:${var.dr_region}:${data.aws_caller_identity.current.account_id}:dbuser:${local.dr_db_resource_id}/shopcloud_checkout"
        },
        {
          Effect   = "Allow"
          Action   = ["sqs:SendMessage"]
          Resource = data.terraform_remote_state.primary.outputs.invoice_queue_arn
        },
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = [
            local.dr_db_secret_arn,
            local.dr_redis_secret_arn,
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
            "cognito-idp:AdminCreateUser",
            "cognito-idp:AdminGetUser",
            "cognito-idp:AdminSetUserPassword",
            "cognito-idp:AdminUpdateUserAttributes",
            "cognito-idp:ListUsers",
          ]
          Resource = [local.customer_pool_arn, local.admin_pool_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = local.dr_cognito_secret_arn
        },
      ]
    })

    admin = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["rds-db:connect"]
          Resource = "arn:aws:rds-db:${var.dr_region}:${data.aws_caller_identity.current.account_id}:dbuser:${local.dr_db_resource_id}/shopcloud_admin"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:ListBucket",
          ]
          Resource = [
            module.s3_invoices_replica.bucket_arn,
            "${module.s3_invoices_replica.bucket_arn}/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = local.dr_db_secret_arn
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
          Resource = [
            "arn:aws:secretsmanager:${var.dr_region}:${data.aws_caller_identity.current.account_id}:secret:shopcloud/*",
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
          Resource = "arn:aws:ssm:${var.dr_region}:${data.aws_caller_identity.current.account_id}:parameter/shopcloud/*"
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

module "eks_dr" {
  source = "../../modules/eks"
  count  = var.enable_dr_compute ? 1 : 0

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

  irsa_service_accounts = {
    catalog = {
      namespace       = "shopcloud"
      service_account = "catalog"
      policy_json     = local.dr_irsa_policies.catalog
    }
    cart = {
      namespace       = "shopcloud"
      service_account = "cart"
      policy_json     = local.dr_irsa_policies.cart
    }
    checkout = {
      namespace       = "shopcloud"
      service_account = "checkout"
      policy_json     = local.dr_irsa_policies.checkout
    }
    auth = {
      namespace       = "shopcloud"
      service_account = "auth"
      policy_json     = local.dr_irsa_policies.auth
    }
    admin = {
      namespace       = "shopcloud"
      service_account = "admin"
      policy_json     = local.dr_irsa_policies.admin
    }
    external-secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets"
      policy_json     = local.dr_irsa_policies.external-secrets
    }
    aws-lb-controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      policy_json     = local.dr_irsa_policies.aws-lb-controller
    }
    cluster-autoscaler = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
      policy_json     = local.dr_irsa_policies.cluster-autoscaler
    }
    keda = {
      namespace       = "keda"
      service_account = "keda-operator"
      policy_json     = local.dr_irsa_policies.keda
    }
  }

  tags = local.common_tags
}
