############################################################
# Invoice pipeline:
#   Checkout -> EventBridge -> SQS -> Lambda -> S3 + SES
#
# All components are free-tier eligible at demo scale:
#   EventBridge : first 14M events/mo free
#   SQS         : 1M req/mo free
#   Lambda      : 1M req + 400K GB-s/mo free
#   SES         : 62K emails/mo free (from Lambda)
############################################################

locals {
  tags = merge(var.tags, { Module = "sqs-lambda" })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------
# Custom EventBridge bus — decouples checkout from SQS
# ----------------------------------------------------------

resource "aws_cloudwatch_event_bus" "shopcloud" {
  name = "${var.name_prefix}-events"
  tags = local.tags
}

# ----------------------------------------------------------
# SQS — main queue + DLQ + EventBridge delivery DLQ
# ----------------------------------------------------------

resource "aws_sqs_queue" "invoice_dlq" {
  name                      = "${var.name_prefix}-invoice-dlq"
  message_retention_seconds = 14 * 24 * 3600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

resource "aws_sqs_queue" "eventbridge_dlq" {
  name                      = "${var.name_prefix}-eventbridge-dlq"
  message_retention_seconds = 14 * 24 * 3600
  sqs_managed_sse_enabled   = true
  tags                      = local.tags
}

resource "aws_sqs_queue" "invoice" {
  name                       = "${var.name_prefix}-invoice-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = var.sqs_message_retention_days * 24 * 3600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.invoice_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.tags, { Name = "${var.name_prefix}-invoice-queue" })
}

# ----------------------------------------------------------
# EventBridge rule: OrderCompleted -> SQS
# ----------------------------------------------------------

resource "aws_cloudwatch_event_rule" "invoice" {
  name           = "${var.name_prefix}-invoice-rule"
  event_bus_name = aws_cloudwatch_event_bus.shopcloud.name
  description    = "Route OrderCompleted events to the invoice queue"

  event_pattern = jsonencode({
    source        = ["shopcloud.checkout"]
    "detail-type" = ["OrderCompleted"]
  })

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "invoice_queue" {
  rule           = aws_cloudwatch_event_rule.invoice.name
  event_bus_name = aws_cloudwatch_event_bus.shopcloud.name
  target_id      = "invoice-queue"
  arn            = aws_sqs_queue.invoice.arn

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }
}

# Allow EventBridge to write to SQS
data "aws_iam_policy_document" "sqs_allow_eventbridge" {
  statement {
    sid    = "AllowEventBridge"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.invoice.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.invoice.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "invoice" {
  queue_url = aws_sqs_queue.invoice.id
  policy    = data.aws_iam_policy_document.sqs_allow_eventbridge.json
}

# Same for the EventBridge DLQ
data "aws_iam_policy_document" "dlq_allow_eventbridge" {
  statement {
    sid    = "AllowEventBridgeDLQ"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.eventbridge_dlq.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.invoice.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "eventbridge_dlq" {
  queue_url = aws_sqs_queue.eventbridge_dlq.id
  policy    = data.aws_iam_policy_document.dlq_allow_eventbridge.json
}
