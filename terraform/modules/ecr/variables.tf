variable "repositories" {
  description = "Repository short names - final name becomes shopcloud/<name>."
  type        = list(string)
  default     = ["catalog", "cart", "checkout", "auth", "admin"]
}

variable "replica_region" {
  description = "Region to replicate images into (e.g. eu-west-1). Set empty to disable replication."
  type        = string
  default     = ""
}

variable "keep_last_n_images" {
  description = "Lifecycle: keep most-recent N tagged images."
  type        = number
  default     = 5
}

variable "untagged_expiry_days" {
  description = "Lifecycle: delete untagged images after N days."
  type        = number
  default     = 3
}

variable "enable_scan_on_push" {
  description = "Enable basic scanning on push (free)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Base tags."
  type        = map(string)
  default     = {}
}
