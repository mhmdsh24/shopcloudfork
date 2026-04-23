############################################################
# Networking module - outputs
############################################################

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ordered by AZ)."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private app/EKS subnet IDs (ordered by AZ)."
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "Private data (RDS/Redis) subnet IDs (ordered by AZ)."
  value       = aws_subnet.private_data[*].id
}

output "public_route_table_id" {
  description = "Route table ID for public subnets."
  value       = aws_route_table.public.id
}

output "private_app_route_table_id" {
  description = "Route table ID for private app subnets."
  value       = aws_route_table.private_app.id
}

output "private_data_route_table_id" {
  description = "Route table ID for private data subnets."
  value       = aws_route_table.private_data.id
}

output "nat_gateway_id" {
  description = "Single NAT Gateway ID."
  value       = aws_nat_gateway.this.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "security_group_ids" {
  description = "Map of canonical SG names to IDs."
  value = {
    public_alb   = aws_security_group.public_alb.id
    internal_alb = aws_security_group.internal_alb.id
    eks_nodes    = aws_security_group.eks_nodes.id
    rds          = aws_security_group.rds.id
    redis        = aws_security_group.redis.id
    vpn          = aws_security_group.vpn.id
    lambda       = aws_security_group.lambda.id
  }
}

output "availability_zones" {
  description = "AZs used by this VPC."
  value       = var.availability_zones
}

output "flow_logs_log_group" {
  description = "CloudWatch log group name for VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}
