variable "name_prefix" {
  description = "Prefix applied to resource names (KMS alias, tags). Does not affect Secrets Manager secret names - see secret_prefix."
  type        = string
}

variable "secret_prefix" {
  description = "Prefix for Secrets Manager secret paths (shopcloud/db/master etc). Defaults to \"shopcloud\" to match the original single-account-per-environment design. Only override this when multiple environments share one AWS account and would otherwise collide on the same secret names - changing it for an environment whose secrets already exist and are in use will not rename the existing secrets or update anything reading them."
  type        = string
  default     = "shopcloud"
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
