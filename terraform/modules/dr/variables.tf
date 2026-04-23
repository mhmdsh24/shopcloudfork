variable "name_prefix" {
  description = "Prefix for resource names (e.g. shopcloud-dr)."
  type        = string
}

variable "vpc_id" {
  description = "DR VPC ID."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (DR ALB)."
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "Private app subnets (ECS Fargate tasks)."
  type        = list(string)
}

variable "public_alb_sg_id" {
  description = "SG for the public DR ALB."
  type        = string
}

variable "eks_nodes_sg_id" {
  description = "Reused as 'ECS task SG' in DR — allows traffic from the DR ALB."
  type        = string
}

variable "services" {
  description = "Services to create Fargate task definitions for. Map of name -> { image, cpu, memory, port }."
  type = map(object({
    image  = string
    cpu    = number
    memory = number
    port   = number
  }))
  default = {
    catalog  = { image = "shopcloud/catalog:latest", cpu = 256, memory = 512, port = 8080 }
    cart     = { image = "shopcloud/cart:latest", cpu = 256, memory = 512, port = 8080 }
    checkout = { image = "shopcloud/checkout:latest", cpu = 256, memory = 512, port = 8080 }
    auth     = { image = "shopcloud/auth:latest", cpu = 256, memory = 512, port = 8080 }
    admin    = { image = "shopcloud/admin:latest", cpu = 256, memory = 512, port = 8080 }
  }
}

variable "account_id" {
  description = "AWS account ID (for ECR image URLs)."
  type        = string
}

variable "region" {
  description = "DR region (e.g. eu-west-1)."
  type        = string
}

variable "alb_certificate_arn" {
  description = "ACM cert for the DR ALB (must be in the DR region)."
  type        = string
  default     = ""
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for DB creds (replica in DR region)."
  type        = string
}

variable "redis_secret_arn" {
  description = "Secrets Manager ARN for Redis creds (replica in DR region)."
  type        = string
}

variable "cognito_secret_arn" {
  description = "Secrets Manager ARN for Cognito config (replica in DR region)."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
