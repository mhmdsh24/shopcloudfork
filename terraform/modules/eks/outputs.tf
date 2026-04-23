output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  value = aws_eks_cluster.this.arn
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  value = aws_iam_openid_connect_provider.cluster.url
}

output "node_group_name" {
  value = aws_eks_node_group.workers.node_group_name
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "irsa_role_arns" {
  description = "Map of logical IRSA name -> IAM role ARN."
  value       = { for k, r in aws_iam_role.irsa : k => r.arn }
}
