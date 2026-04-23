############################################################
# VPC Endpoints
#   - Gateway endpoints (S3, DynamoDB) are FREE - always on.
#   - Interface endpoints (ECR, STS) are ~$7.50/mo each - opt-in.
############################################################

# ---------- Gateway endpoints (free) ----------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [aws_route_table.private_app.id],
    [aws_route_table.private_data.id],
    [aws_route_table.public.id],
  )

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_data.id,
    aws_route_table.public.id,
  ]

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpce-dynamodb"
  })
}

# ---------- Interface endpoints (paid, opt-in) ----------

resource "aws_security_group" "vpce" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${var.name_prefix}-sg-vpce"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-sg-vpce"
  })
}

locals {
  interface_services = var.enable_interface_endpoints ? [
    "ecr.api",
    "ecr.dkr",
    "sts",
  ] : []
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = aws_security_group.vpce[*].id

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpce-${replace(each.value, ".", "-")}"
  })
}
