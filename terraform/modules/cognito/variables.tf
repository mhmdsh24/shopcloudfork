variable "name_prefix" {
  description = "Prefix for Cognito pool names."
  type        = string
}

variable "callback_urls" {
  description = "Allowed callback URLs for the customer web client."
  type        = list(string)
  default     = ["https://app.shopcloud.com/auth/callback"]
}

variable "logout_urls" {
  description = "Allowed logout URLs for the customer web client."
  type        = list(string)
  default     = ["https://app.shopcloud.com/auth/logout"]
}

variable "admin_callback_urls" {
  description = "Allowed callback URLs for the admin client."
  type        = list(string)
  default     = ["https://admin.internal.shopcloud.com/auth/callback"]
}

variable "admin_logout_urls" {
  description = "Allowed logout URLs for the admin client."
  type        = list(string)
  default     = ["https://admin.internal.shopcloud.com/auth/logout"]
}

variable "cognito_config_secret_id" {
  description = "Secrets Manager secret to populate with pool IDs + client IDs."
  type        = string
  default     = null
}

variable "populate_secret" {
  description = "Write the final cognito config into var.cognito_config_secret_id at apply time."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
