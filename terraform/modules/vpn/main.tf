############################################################
# AWS Client VPN endpoint - mutual TLS auth, split tunnel,
# single subnet association to keep costs down.
############################################################

locals {
  tags = merge(var.tags, { Module = "vpn" })
}

resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/client-vpn/${var.name_prefix}"
  retention_in_days = var.log_group_retention_days
  tags              = local.tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.name_prefix} admin VPN"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.client_cidr
  split_tunnel           = true
  dns_servers            = var.dns_servers
  transport_protocol     = "udp"
  vpc_id                 = null
  vpn_port               = 443
  security_group_ids     = var.vpc_security_group_ids
  session_timeout_hours  = 12

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_certificate_arn
  }

  dynamic "authentication_options" {
    for_each = var.mfa_saml_provider_arn != "" ? [1] : []
    content {
      type              = "federated-authentication"
      saml_provider_arn = var.mfa_saml_provider_arn
    }
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpn" })
}

resource "aws_ec2_client_vpn_network_association" "this" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_id
}

resource "aws_ec2_client_vpn_authorization_rule" "this" {
  for_each = toset(var.authorized_cidrs)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = each.value
  authorize_all_groups   = true
  description            = "Allow VPN clients to reach ${each.value}"
}
