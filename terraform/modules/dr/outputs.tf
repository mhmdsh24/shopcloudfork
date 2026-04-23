output "alb_dns_name" {
  value = aws_lb.public.dns_name
}

output "alb_zone_id" {
  value = aws_lb.public.zone_id
}

output "alb_arn" {
  value = aws_lb.public.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.dr.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.dr.arn
}

output "service_names" {
  value = [for s in aws_ecs_service.svc : s.name]
}

output "target_group_arns" {
  value = { for k, v in aws_lb_target_group.svc : k => v.arn }
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}
