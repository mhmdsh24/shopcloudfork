output "peering_connection_id" {
  description = "Cross-region VPC peering connection ID."
  value       = module.peering.peering_connection_id
}

output "peering_connection_status" {
  description = "Cross-region peering status (should be 'active')."
  value       = module.peering.peering_connection_status
}
