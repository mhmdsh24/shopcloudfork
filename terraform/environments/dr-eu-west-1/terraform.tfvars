############################################################
# DR region (eu-west-1) variable values.
############################################################

project_name = "shopcloud"
environment  = "production"

primary_region     = "us-east-1"
dr_region          = "eu-west-1"
availability_zones = ["eu-west-1a", "eu-west-1b"]

vpc_cidr                  = "10.1.0.0/16"
public_subnet_cidrs       = ["10.1.1.0/24", "10.1.2.0/24"]
private_app_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24"]
private_data_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24"]
vpn_client_cidr           = "10.0.100.0/22"

eks_cluster_name = "shopcloud-dr"

enable_interface_endpoints = false

enable_dr_replica = true
enable_dr_compute = true

eks_node_instance_types = ["t3.small"]
eks_node_capacity_type  = "ON_DEMAND"
eks_node_desired_size   = 2
eks_node_min_size       = 2
eks_node_max_size       = 4
