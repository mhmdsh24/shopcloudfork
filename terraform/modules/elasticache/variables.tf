variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "node_type" {
  description = "Cache node type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Number of cluster nodes. 1 = no HA (cost-optimized), 2+ = multi-AZ."
  type        = number
  default     = 1
}

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "subnet_ids" {
  description = "Private data subnet IDs."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs."
  type        = list(string)
}

variable "auth_token" {
  description = "Redis auth token (from secrets module)."
  type        = string
  sensitive   = true
}

variable "redis_secret_id" {
  description = "Secrets Manager secret ID to populate with endpoint + auth token. Optional."
  type        = string
  default     = null
}

variable "populate_secret" {
  description = "Write the final Redis connection info into var.redis_secret_id at apply time."
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ARN/ID for at-rest encryption. Null = AWS-managed."
  type        = string
  default     = null
}

variable "snapshot_retention_days" {
  description = "Number of days snapshots are retained."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
