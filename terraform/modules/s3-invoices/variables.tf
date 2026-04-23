variable "bucket_name" {
  description = "Fully-qualified bucket name (e.g. shopcloud-invoices-781863099565)."
  type        = string
}

variable "replica_bucket_arn" {
  description = "ARN of the destination bucket for cross-region replication. Empty = disable CRR."
  type        = string
  default     = ""
}

variable "expire_after_days" {
  description = "Lifecycle: expire objects after N days. 0 = never."
  type        = number
  default     = 365
}

variable "tags" {
  type    = map(string)
  default = {}
}
