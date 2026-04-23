output "cluster_id" {
  value = aws_rds_cluster.this.id
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "cluster_resource_id" {
  description = "Cluster resource ID — used for IAM DB auth."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "global_cluster_id" {
  description = "Global cluster ID (populated only on primary when global_cluster_id is set)."
  value       = local.creates_global_cluster ? aws_rds_global_cluster.this[0].id : null
}

output "global_cluster_arn" {
  value = local.creates_global_cluster ? aws_rds_global_cluster.this[0].arn : null
}
