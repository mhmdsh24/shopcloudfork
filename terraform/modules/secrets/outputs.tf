output "kms_key_id" {
  description = "KMS key ID (null when create_kms_key = false)."
  value       = local.kms_key_id
}

output "kms_key_arn" {
  description = "KMS key ARN (null when create_kms_key = false)."
  value       = local.kms_key_arn
}

output "db_secret_arn" {
  description = "ARN of shopcloud/db/master."
  value       = aws_secretsmanager_secret.db_master.arn
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db_master.name
}

output "redis_secret_arn" {
  description = "ARN of shopcloud/redis/auth."
  value       = aws_secretsmanager_secret.redis_auth.arn
}

output "redis_secret_name" {
  value = aws_secretsmanager_secret.redis_auth.name
}

output "cognito_secret_arn" {
  description = "ARN of shopcloud/cognito/config."
  value       = aws_secretsmanager_secret.cognito_config.arn
}

output "cognito_secret_name" {
  value = aws_secretsmanager_secret.cognito_config.name
}

output "ssm_parameter_arns" {
  description = "SSM parameter ARNs for IAM scoping."
  value = [
    aws_ssm_parameter.environment.arn,
    aws_ssm_parameter.log_level.arn,
  ]
}

output "db_bootstrap_password" {
  description = "Bootstrap password used for initial RDS creation. Do not log."
  value       = random_password.db_bootstrap.result
  sensitive   = true
}

output "redis_bootstrap_auth_token" {
  description = "Bootstrap auth token for ElastiCache."
  value       = random_password.redis_auth_bootstrap.result
  sensitive   = true
}
