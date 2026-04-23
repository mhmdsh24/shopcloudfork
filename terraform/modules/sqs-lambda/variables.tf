variable "name_prefix" {
  description = "Prefix applied to all resource names."
  type        = string
}

variable "invoice_bucket_id" {
  description = "S3 bucket that receives generated PDF invoices."
  type        = string
}

variable "invoice_bucket_arn" {
  description = "ARN of the invoice bucket."
  type        = string
}

variable "ses_domain" {
  description = "Verified SES domain used as From address."
  type        = string
  default     = "shopcloud.com"
}

variable "ses_from_address" {
  description = "From address for outbound invoice emails."
  type        = string
  default     = "invoices@shopcloud.com"
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for the invoice generator. -1 = no reservation (use the account's unreserved pool). New AWS accounts have a 10-concurrency quota and will reject any positive reservation because it would drop unreserved capacity below the 10-unit floor."
  type        = number
  default     = -1
}

variable "lambda_memory_mb" {
  description = "Lambda memory in MB."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 60
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout - must be > lambda timeout."
  type        = number
  default     = 300
}

variable "sqs_message_retention_days" {
  description = "SQS message retention window in days."
  type        = number
  default     = 4
}

variable "tags" {
  type    = map(string)
  default = {}
}
