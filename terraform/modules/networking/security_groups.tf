############################################################
# Security Groups
#   sg-public-alb    - public internet-facing ALB
#   sg-internal-alb  - admin ALB, only reachable from VPN
#   sg-eks-nodes     - EKS worker nodes
#   sg-rds           - PostgreSQL, only from EKS nodes
#   sg-redis         - ElastiCache Redis, only from EKS nodes
#   sg-vpn           - Client VPN endpoint
#   sg-lambda        - Lambda in VPC (egress only, used by invoice pipeline if needed)
############################################################

# -------- Public ALB --------
resource "aws_security_group" "public_alb" {
  name        = "${var.name_prefix}-sg-public-alb"
  description = "Public ALB - 443 from anywhere"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-public-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_https" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTPS from internet"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_http" {
  security_group_id = aws_security_group.public_alb.id
  description       = "HTTP from internet (redirect to 443 by listener)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "public_alb_egress" {
  security_group_id = aws_security_group.public_alb.id
  description       = "All to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

# -------- Internal ALB --------
resource "aws_security_group" "internal_alb" {
  name        = "${var.name_prefix}-sg-internal-alb"
  description = "Internal ALB - 443 only from VPN client CIDR"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-internal-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_vpn" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "HTTPS from VPN clients"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpn_client_cidr
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_egress" {
  security_group_id = aws_security_group.internal_alb.id
  description       = "All to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

# -------- EKS nodes --------
resource "aws_security_group" "eks_nodes" {
  name        = "${var.name_prefix}-sg-eks-nodes"
  description = "EKS worker nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-eks-nodes" })
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_public_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Traffic from public ALB"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.public_alb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_internal_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Traffic from internal ALB"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.internal_alb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_from_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Node-to-node (pod-to-pod) traffic"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_vpc_security_group_egress_rule" "eks_egress" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -------- RDS --------
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-sg-rds"
  description = "PostgreSQL - only from EKS nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from EKS nodes"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# -------- Redis --------
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-sg-redis"
  description = "ElastiCache Redis - only from EKS nodes"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-redis" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from EKS nodes"
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# -------- Client VPN --------
resource "aws_security_group" "vpn" {
  name        = "${var.name_prefix}-sg-vpn"
  description = "Client VPN endpoint"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-vpn" })
}

resource "aws_vpc_security_group_ingress_rule" "vpn_https" {
  security_group_id = aws_security_group.vpn.id
  description       = "OpenVPN over 443 from internet"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vpn_egress" {
  security_group_id = aws_security_group.vpn.id
  description       = "All to VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

# -------- Lambda (invoice pipeline) --------
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-sg-lambda"
  description = "Lambda egress only (S3, SES, Secrets Manager)"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name_prefix}-sg-lambda" })
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS outbound to AWS APIs"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}
