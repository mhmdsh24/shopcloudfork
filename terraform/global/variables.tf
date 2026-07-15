variable "project_name" {
  description = "Project slug."
  type        = string
  default     = "shopcloud"
}

variable "environment" {
  description = "Logical environment label."
  type        = string
  default     = "production"
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket" {
  description = "S3 bucket holding all Terraform state files."
  type        = string
  default     = "shopcloud-tfstate-268810572260"
}
