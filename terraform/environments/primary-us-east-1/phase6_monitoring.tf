############################################################
# Phase 6 — Observability
############################################################

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix    = local.name_prefix
  alert_email    = var.alert_email
  primary_region = var.primary_region

  aurora_cluster_id       = module.rds.cluster_id
  sqs_queue_name          = element(split("/", module.sqs_lambda.invoice_queue_arn), 5)
  sqs_dlq_name            = "${local.name_prefix}-invoice-dlq"
  lambda_function_name    = module.sqs_lambda.lambda_function_name
  route53_health_check_id = module.dns.primary_health_check_id

  enable_cloudtrail = var.enable_cloudtrail
  state_bucket_name = "shopcloud-tfstate-${data.aws_caller_identity.current.account_id}"

  tags = local.common_tags
}
