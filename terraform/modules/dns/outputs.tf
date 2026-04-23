output "public_zone_id" {
  value = aws_route53_zone.public.zone_id
}

output "public_zone_name_servers" {
  description = "Name servers to configure at your registrar."
  value       = aws_route53_zone.public.name_servers
}

output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "primary_health_check_id" {
  value = try(aws_route53_health_check.primary[0].id, null)
}
