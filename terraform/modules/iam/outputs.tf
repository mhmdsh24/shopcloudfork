output "github_oidc_provider_arn" {
  value = local.github_oidc_provider_arn
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "github_deploy_role_name" {
  value = aws_iam_role.github_deploy.name
}
