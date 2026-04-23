variable "name_prefix" {
  description = "Prefix applied to secret names."
  type        = string
}

variable "create_kms_key" {
  description = "Create a dedicated customer-managed KMS key ($1/mo). Set false to use AWS-managed keys everywhere (saves $1/mo)."
  type        = bool
  default     = true
}

variable "replica_region" {
  description = "Region to replicate secrets into (e.g. eu-west-1). Set to null/empty to disable replication."
  type        = string
  default     = null
}

variable "enable_db_rotation" {
  description = "Enable automatic rotation on shopcloud/db/master. Requires a rotation Lambda (not created here)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Base tags."
  type        = map(string)
  default     = {}
}
