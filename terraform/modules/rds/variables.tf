############################################################
# rds module - Standard RDS PostgreSQL.
# Roles:
#   standalone : single-region, no cross-region replica.
#   primary    : source of a cross-region read replica (DR).
#   replica    : cross-region read replica in another region.
############################################################

variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "role" {
  description = "One of: standalone | primary | replica."
  type        = string
  default     = "standalone"
  validation {
    condition     = contains(["standalone", "primary", "replica"], var.role)
    error_message = "role must be standalone, primary, or replica."
  }
}

############################################################
# Engine / sizing (writer-only; replica inherits from source)
############################################################

variable "engine_version" {
  description = "PostgreSQL engine version (writer only)."
  type        = string
  default     = "15.7"
}

variable "parameter_group_family" {
  description = "DB parameter group family (must match engine version)."
  type        = string
  default     = "postgres15"
}

variable "instance_class" {
  description = "DB instance class. db.t3.micro is AWS Free Tier eligible."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage_gb" {
  description = "Allocated storage in GB. 20 GB is Free Tier eligible."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Upper bound for storage autoscaling. Null to disable autoscaling."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "gp2 is Free Tier eligible; gp3 is cheaper on sustained use but out of free tier."
  type        = string
  default     = "gp2"
}

############################################################
# Credentials (writer-only)
############################################################

variable "database_name" {
  description = "Initial database name (writer only)."
  type        = string
  default     = "shopcloud"
}

variable "master_username" {
  description = "Master username (writer only)."
  type        = string
  default     = "shopcloud_admin"
}

variable "master_password" {
  description = "Master password (writer only). Pulled from the secrets module."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_secret_id" {
  description = "Secrets Manager secret ID to overwrite with final connection info. Writer only."
  type        = string
  default     = null
}

############################################################
# Replica wiring
############################################################

variable "source_db_arn" {
  description = "Full ARN of the source DB instance. Required when role = replica (cross-region read replica)."
  type        = string
  default     = null
}

############################################################
# Networking
############################################################

variable "subnet_ids" {
  description = "Private data subnet IDs."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "SG IDs to attach to the DB instance."
  type        = list(string)
}

############################################################
# Encryption
############################################################

variable "kms_key_id" {
  description = "KMS key for storage encryption. Null = AWS-managed key (free)."
  type        = string
  default     = null
}

############################################################
# HA / backups
############################################################

variable "multi_az" {
  description = "Enable Multi-AZ standby. Not Free Tier eligible - the standby doubles hourly cost."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention in days (writer only). 0 disables backups."
  type        = number
  default     = 7
}

variable "preferred_backup_window" {
  description = "Preferred backup window (UTC, writer only)."
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

variable "tags" {
  type    = map(string)
  default = {}
}
