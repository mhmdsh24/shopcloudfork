variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "node_ami_type" {
  description = "EKS managed node AMI type. AL2023 keeps Kubernetes 1.35 nodes on cgroup v2."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "subnet_ids" {
  description = "Private app subnet IDs where the cluster ENIs and nodes live."
  type        = list(string)
}

variable "node_security_group_ids" {
  description = "Additional SG IDs attached to the node group (the networking module's sg-eks-nodes)."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "Source CIDRs allowed to call the public EKS API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the spot node group."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_capacity_type" {
  description = "SPOT or ON_DEMAND."
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_gb" {
  type    = number
  default = 20
}

variable "cluster_log_types" {
  description = "Control plane log types to enable."
  type        = list(string)
  default     = ["api", "audit"]
}

variable "cluster_log_retention_days" {
  type    = number
  default = 7
}

variable "kms_key_arn" {
  description = "KMS key for envelope encryption of secrets. Null = AWS-managed."
  type        = string
  default     = null
}

# ----- Service accounts that should get IRSA roles -----

variable "irsa_service_accounts" {
  description = "Map of IRSA role name -> { namespace, service_account, policy_json }."
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
  }))
  default = {}
}

variable "cluster_admin_iam_arns" {
  description = "List of IAM role/user ARNs to grant EKS cluster-admin access via access entries."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
