############################################################
# rds module — Aurora PostgreSQL cluster.
# Can operate in three modes:
#   role = "standalone" : single-region cluster (no Global DB).
#   role = "primary"    : primary cluster of a Global Database.
#   role = "secondary"  : secondary cluster of a Global Database (DR).
############################################################

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "role" {
  description = "One of: standalone | primary | secondary."
  type        = string
  default     = "primary"
  validation {
    condition     = contains(["standalone", "primary", "secondary"], var.role)
    error_message = "role must be standalone, primary, or secondary."
  }
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "Instance class for the cluster writer/reader."
  type        = string
  default     = "db.t4g.medium"
}

variable "database_name" {
  description = "Initial database name (only used on primary/standalone)."
  type        = string
  default     = "shopcloud"
}

variable "master_username" {
  description = "Master username (only used on primary/standalone)."
  type        = string
  default     = "shopcloud_admin"
}

variable "master_password" {
  description = "Master password (only used on primary/standalone). Pulled from the secrets module."
  type        = string
  default     = null
  sensitive   = true
}

variable "global_cluster_id" {
  description = "Global cluster identifier. Set when role = primary (creates it) or secondary (joins existing)."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private data subnet IDs."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "SG IDs to attach to the cluster."
  type        = list(string)
}

variable "kms_key_id" {
  description = "KMS key for storage encryption. Null = AWS-managed key."
  type        = string
  default     = null
}

variable "db_secret_id" {
  description = "Secrets Manager secret ID to overwrite with final DB connection info. Only used on primary/standalone."
  type        = string
  default     = null
}

variable "backup_retention_days" {
  description = "Backup retention in days."
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Preferred backup window (UTC)."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Preferred maintenance window (UTC)."
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy. Set true for non-prod/teardown."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights (7-day retention is free)."
  type        = bool
  default     = true
}

variable "instance_count" {
  description = "Number of Aurora instances in this cluster (1 = writer only)."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
