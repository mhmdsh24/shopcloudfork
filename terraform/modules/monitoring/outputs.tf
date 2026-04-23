output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudtrail_arn" {
  value = try(aws_cloudtrail.this[0].arn, null)
}
