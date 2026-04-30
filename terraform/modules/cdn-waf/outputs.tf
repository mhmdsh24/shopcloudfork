output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosted_zone_id" {
  value = aws_cloudfront_distribution.this.hosted_zone_id
}

output "web_acl_arn" {
  value = aws_wafv2_web_acl.cloudfront.arn
}

output "certificate_arn" {
  value = length(aws_acm_certificate_validation.cloudfront) > 0 ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : null
}
