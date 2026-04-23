############################################################
# Monitoring - SNS alerts + critical CloudWatch alarms.
############################################################

locals {
  tags = merge(var.tags, { Module = "monitoring" })
}

data "aws_caller_identity" "current" {}

# ----------------------------------------------------------
# SNS topic + email subscription (confirmation required)
# ----------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ----------------------------------------------------------
# Alarms
# ----------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = var.enable_rds_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-rds-cpu-high"
  alarm_description   = "RDS CPU > 80% for 10 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  period              = 300
  statistic           = "Average"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  count = var.enable_rds_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-rds-free-storage-low"
  alarm_description   = "RDS free storage < 2 GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 2 * 1024 * 1024 * 1024 # 2 GB in bytes
  period              = 300
  statistic           = "Minimum"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"

  dimensions = {
    DBInstanceIdentifier = var.db_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count = var.enable_dlq_alarm ? 1 : 0

  alarm_name          = "${var.name_prefix}-invoice-dlq-not-empty"
  alarm_description   = "Invoice DLQ has messages (indicates permanent failure)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 300
  statistic           = "Maximum"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"

  dimensions = {
    QueueName = var.sqs_dlq_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_lambda_alarm ? 1 : 0

  alarm_name          = "${var.name_prefix}-invoice-lambda-errors"
  alarm_description   = "Invoice Lambda errors > 3 in 5 min"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 3
  period              = 300
  statistic           = "Sum"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

resource "aws_cloudwatch_metric_alarm" "route53_health" {
  count = var.enable_route53_alarm ? 1 : 0

  provider = aws

  alarm_name          = "${var.name_prefix}-route53-health"
  alarm_description   = "Route 53 primary health check failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  threshold           = 1
  period              = 60
  statistic           = "Minimum"
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"

  dimensions = {
    HealthCheckId = var.route53_health_check_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

# ----------------------------------------------------------
# CloudTrail - single multi-region trail, management events only
# ----------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_bucket" {
  count = var.enable_cloudtrail && var.state_bucket_name != "" ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail && var.state_bucket_name != "" ? 1 : 0

  bucket = var.state_bucket_name
  policy = data.aws_iam_policy_document.cloudtrail_bucket[0].json
}

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail && var.state_bucket_name != "" ? 1 : 0

  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = var.state_bucket_name
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = local.tags
}
