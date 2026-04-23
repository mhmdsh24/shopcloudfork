############################################################
# Cross-region VPC peering — inputs
############################################################

variable "name" {
  description = "Name applied to the peering connection."
  type        = string
}

variable "requester_vpc_id" {
  description = "VPC ID of the requester (primary region)."
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR of the requester VPC (installed as destination on accepter side)."
  type        = string
}

variable "requester_route_table_ids" {
  description = "Route table IDs on the requester side that need a route to the accepter VPC."
  type        = list(string)
}

variable "accepter_vpc_id" {
  description = "VPC ID of the accepter (DR region)."
  type        = string
}

variable "accepter_vpc_cidr" {
  description = "CIDR of the accepter VPC (installed as destination on requester side)."
  type        = string
}

variable "accepter_route_table_ids" {
  description = "Route table IDs on the accepter side that need a route to the requester VPC."
  type        = list(string)
}

variable "accepter_region" {
  description = "AWS region of the accepter VPC (e.g. eu-west-1)."
  type        = string
}

variable "tags" {
  description = "Tags applied to the peering connection on both sides."
  type        = map(string)
  default     = {}
}
