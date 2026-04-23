variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the alerts SNS topic."
  type        = string
  default     = ""
}

variable "aurora_cluster_id" {
  description = "Aurora cluster ID to monitor."
  type        = string
  default     = ""
}

variable "sqs_queue_name" {
  description = "SQS invoice queue name to monitor for DLQ backlog and depth."
  type        = string
  default     = ""
}

variable "sqs_dlq_name" {
  description = "SQS DLQ name. Alarm fires when any messages land here."
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Invoice Lambda function name."
  type        = string
  default     = ""
}

variable "route53_health_check_id" {
  description = "Route 53 health check ID to monitor."
  type        = string
  default     = ""
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "enable_cloudtrail" {
  description = "Create a single-trail multi-region CloudTrail (free for management events)."
  type        = bool
  default     = true
}

variable "state_bucket_name" {
  description = "S3 bucket that CloudTrail will log into (re-use the terraform state bucket)."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
