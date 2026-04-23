output "peering_connection_id" {
  description = "ID of the cross-region VPC peering connection."
  value       = aws_vpc_peering_connection.this.id
}

output "peering_connection_status" {
  description = "Current status of the peering connection (from the accepter side)."
  value       = aws_vpc_peering_connection_accepter.this.accept_status
}
