############################################################
# EKS module - cluster + spot node group + OIDC + addons.
############################################################

locals {
  tags = merge(var.tags, { Module = "eks" })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------
# Cluster IAM role
# ----------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ----------------------------------------------------------
# Cluster log group with short retention
# ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  tags              = local.tags
}

# ----------------------------------------------------------
# EKS cluster
# ----------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
  }

  enabled_cluster_log_types = var.cluster_log_types

  dynamic "encryption_config" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = var.kms_key_arn
      }
    }
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]

  tags = merge(local.tags, { Name = var.cluster_name })
}

# ----------------------------------------------------------
# OIDC provider (for IRSA)
# ----------------------------------------------------------

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = merge(local.tags, { Name = "${var.cluster_name}-oidc" })
}

# ----------------------------------------------------------
# Node IAM role
# ----------------------------------------------------------

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ----------------------------------------------------------
# Launch template - IMDSv2 enforced
# ----------------------------------------------------------

resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.cluster_name}-nodes-"
  update_default_version = true

  # Must include the EKS-managed cluster security group so the
  # node's kubelet can reach the control-plane ENIs on 443/10250.
  # When a custom launch template is used, AWS stops auto-
  # attaching this SG - we have to add it explicitly. Without
  # it the node boots fine but never registers with the cluster.
  vpc_security_group_ids = concat(
    var.node_security_group_ids,
    [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id],
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = false
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.cluster_name}-node" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }
}

# ----------------------------------------------------------
# Managed spot node group
# ----------------------------------------------------------

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-spot-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  labels = {
    role        = "workload"
    environment = "production"
    lifecycle   = "spot"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_ssm,
  ]

  tags = local.tags

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ----------------------------------------------------------
# Cluster autoscaler discovery tags on the underlying ASG.
# Managed node groups create the ASG implicitly; cluster-autoscaler
# needs `k8s.io/cluster-autoscaler/enabled = true` and
# `k8s.io/cluster-autoscaler/<cluster-name> = owned` to pick it up.
# ----------------------------------------------------------

resource "aws_autoscaling_group_tag" "autoscaler_enabled" {
  autoscaling_group_name = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "autoscaler_cluster" {
  autoscaling_group_name = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}

# ----------------------------------------------------------
# Add-ons
# ----------------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = null

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  depends_on = [aws_eks_node_group.workers]

  tags = local.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = null

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.workers]
  tags       = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = null

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.workers]
  tags       = local.tags
}

# ----------------------------------------------------------
# IRSA - one IAM role per service account entry
# ----------------------------------------------------------

locals {
  oidc_provider_name = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

data "aws_iam_policy_document" "irsa_assume" {
  for_each = var.irsa_service_accounts

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_name}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_name}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = var.irsa_service_accounts

  name               = "${var.cluster_name}-irsa-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume[each.key].json
  tags               = merge(local.tags, { ServiceAccount = "${each.value.namespace}/${each.value.service_account}" })
}

resource "aws_iam_role_policy" "irsa" {
  for_each = var.irsa_service_accounts

  name   = "${var.cluster_name}-irsa-${each.key}"
  role   = aws_iam_role.irsa[each.key].id
  policy = each.value.policy_json
}
