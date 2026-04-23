############################################################
# Lambda invoice generator — inline zipped Python handler.
#   * reads SQS messages (5 at a time)
#   * builds a PDF with reportlab
#   * writes it to S3
#   * sends via SES
############################################################

# ----------------------------------------------------------
# Package the handler code from this module
# ----------------------------------------------------------

data "archive_file" "invoice_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/invoice-generator.zip"
}

# ----------------------------------------------------------
# Execution role + policy
# ----------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-invoice-generator"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid    = "SQS"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.invoice.arn]
  }

  statement {
    sid    = "S3PutInvoices"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = ["${var.invoice_bucket_arn}/*"]
  }

  statement {
    sid    = "SESSend"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name_prefix}-invoice-generator"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ----------------------------------------------------------
# Log group with 7-day retention
# ----------------------------------------------------------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-invoice-generator"
  retention_in_days = 7
  tags              = local.tags
}

# ----------------------------------------------------------
# Function
# ----------------------------------------------------------

resource "aws_lambda_function" "invoice" {
  function_name = "${var.name_prefix}-invoice-generator"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.invoice_lambda.output_path
  source_code_hash = data.archive_file.invoice_lambda.output_base64sha256

  memory_size                    = var.lambda_memory_mb
  timeout                        = var.lambda_timeout_seconds
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  environment {
    variables = {
      INVOICE_BUCKET   = var.invoice_bucket_id
      SES_FROM_ADDRESS = var.ses_from_address
      LOG_LEVEL        = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda,
  ]

  tags = local.tags
}

# ----------------------------------------------------------
# SQS event source mapping
# ----------------------------------------------------------

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = aws_sqs_queue.invoice.arn
  function_name                      = aws_lambda_function.invoice.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# ----------------------------------------------------------
# SES — domain identity (requires manual DNS record creation
# outside this module).
# ----------------------------------------------------------

resource "aws_ses_domain_identity" "this" {
  domain = var.ses_domain
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}
