############################################################
# Cognito - customer + admin user pools.
# Free for the first 50,000 MAUs.
############################################################

locals {
  tags = merge(var.tags, { Module = "cognito" })
}

data "aws_region" "current" {}

############################################################
# Customer pool - email sign-in, optional TOTP MFA
############################################################

resource "aws_cognito_user_pool" "customers" {
  name = "${var.name_prefix}-customers"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Verify your ShopCloud account"
    email_message        = "Your ShopCloud verification code is {####}"
  }

  # Use Cognito default email (free, 50/day) - swap to SES for production.

  deletion_protection = "INACTIVE"

  tags = merge(local.tags, { Name = "${var.name_prefix}-customers" })
}

resource "aws_cognito_user_pool_client" "customer_web" {
  name         = "${var.name_prefix}-customer-web"
  user_pool_id = aws_cognito_user_pool.customers.id

  generate_secret                               = false
  prevent_user_existence_errors                 = "ENABLED"
  enable_token_revocation                       = true
  enable_propagate_additional_user_context_data = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  supported_identity_providers         = ["COGNITO"]
}

############################################################
# Admin pool - MFA required, shorter tokens, no self-signup
############################################################

resource "aws_cognito_user_pool" "admins" {
  name = "${var.name_prefix}-admins"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 16
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  schema {
    name                = "role"
    attribute_data_type = "String"
    required            = false
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 32
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  deletion_protection = "INACTIVE"

  tags = merge(local.tags, { Name = "${var.name_prefix}-admins" })
}

resource "aws_cognito_user_pool_client" "admin_web" {
  name         = "${var.name_prefix}-admin-web"
  user_pool_id = aws_cognito_user_pool.admins.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 30
  id_token_validity      = 30
  refresh_token_validity = 7
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  callback_urls                        = var.admin_callback_urls
  logout_urls                          = var.admin_logout_urls
  supported_identity_providers         = ["COGNITO"]
}

############################################################
# Persist IDs into the cognito_config secret
############################################################

resource "aws_secretsmanager_secret_version" "cognito_final" {
  # Static boolean - populate_secret is known at plan time; the secret_id
  # itself is a computed ARN so it can't appear in the count expression.
  count = var.populate_secret ? 1 : 0

  secret_id = var.cognito_config_secret_id
  secret_string = jsonencode({
    customer_pool_id = aws_cognito_user_pool.customers.id
    customer_client  = aws_cognito_user_pool_client.customer_web.id
    admin_pool_id    = aws_cognito_user_pool.admins.id
    admin_client     = aws_cognito_user_pool_client.admin_web.id
    region           = data.aws_region.current.region
  })
}
