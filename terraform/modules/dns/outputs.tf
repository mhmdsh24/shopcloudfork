output "public_zone_id" {
  value = local.public_zone_id
}

output "public_zone_name_servers" {
  description = "Name servers to configure at your registrar."
  value       = local.public_zone_name_servers
}

output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "origin_hostname" {
  description = "CloudFront origin hostname that resolves to regional ALBs when CloudFront regional origin latency routing is active."
  value       = local.origin_hostname
}

output "public_routing_mode" {
  description = "How public apex/app records are routed."
  value       = local.public_routing_mode
}
