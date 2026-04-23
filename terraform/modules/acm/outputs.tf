output "certificate_arn" {
  description = "Validated ACM certificate ARN."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  value = aws_acm_certificate.this.domain_name
}
