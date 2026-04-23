output "event_bus_name" {
  value = aws_cloudwatch_event_bus.shopcloud.name
}

output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.shopcloud.arn
}

output "invoice_queue_url" {
  value = aws_sqs_queue.invoice.url
}

output "invoice_queue_arn" {
  value = aws_sqs_queue.invoice.arn
}

output "invoice_dlq_arn" {
  value = aws_sqs_queue.invoice_dlq.arn
}

output "eventbridge_dlq_arn" {
  value = aws_sqs_queue.eventbridge_dlq.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.invoice.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.invoice.function_name
}

output "ses_domain_verification_token" {
  description = "Add a TXT record _amazonses.<domain> with this value to verify SES."
  value       = aws_ses_domain_identity.this.verification_token
}

output "ses_dkim_tokens" {
  description = "Add three CNAMEs <token>._domainkey.<domain> -> <token>.dkim.amazonses.com"
  value       = aws_ses_domain_dkim.this.dkim_tokens
}
