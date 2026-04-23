############################################################
# Cross-region VPC peering: requester <-> accepter
#
# Usage: pass two provider aliases - `aws.requester` (primary region)
# and `aws.accepter` (DR region). Module creates the connection on
# the requester side, accepts it on the accepter side, and installs
# symmetric routes on the route tables you give it.
############################################################

locals {
  tags = merge(var.tags, { Module = "peering" })
}

# --- Requester side: create the peering request ------------------------

resource "aws_vpc_peering_connection" "this" {
  provider = aws.requester

  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  peer_region = var.accepter_region
  auto_accept = false

  tags = merge(local.tags, {
    Name = "${var.name}-requester"
    Side = "requester"
  })
}

# --- Accepter side: accept the peering request -------------------------

resource "aws_vpc_peering_connection_accepter" "this" {
  provider = aws.accepter

  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
  auto_accept               = true

  tags = merge(local.tags, {
    Name = "${var.name}-accepter"
    Side = "accepter"
  })
}

# --- Route propagation ------------------------------------------------

resource "aws_route" "requester_to_accepter" {
  provider = aws.requester
  for_each = toset(var.requester_route_table_ids)

  route_table_id            = each.value
  destination_cidr_block    = var.accepter_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}

resource "aws_route" "accepter_to_requester" {
  provider = aws.accepter
  for_each = toset(var.accepter_route_table_ids)

  route_table_id            = each.value
  destination_cidr_block    = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.this.vpc_peering_connection_id

  depends_on = [aws_vpc_peering_connection_accepter.this]
}
