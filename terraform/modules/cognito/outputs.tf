output "customer_pool_id" {
  value = aws_cognito_user_pool.customers.id
}

output "customer_pool_arn" {
  value = aws_cognito_user_pool.customers.arn
}

output "customer_client_id" {
  value = aws_cognito_user_pool_client.customer_web.id
}

output "admin_pool_id" {
  value = aws_cognito_user_pool.admins.id
}

output "admin_pool_arn" {
  value = aws_cognito_user_pool.admins.arn
}

output "admin_client_id" {
  value = aws_cognito_user_pool_client.admin_web.id
}
