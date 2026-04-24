############################################################
# Invoice pipeline:
#   Checkout -> SQS -> Lambda -> S3 + SES
############################################################

locals {
  tags = merge(var.tags, { Module = "sqs-lambda" })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----------------------------------------------------------
# SQS - main queue + DLQ
# ----------------------------------------------------------

resource "aws_sqs_queue" "invoice_dlq" {
  name                      = "${var.name_prefix}-invoice-dlq"
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

