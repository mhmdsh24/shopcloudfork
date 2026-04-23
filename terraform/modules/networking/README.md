# Module: `networking`

Provisions the per-region network foundation for ShopCloud:

- `aws_vpc` with DNS hostnames + support enabled
- Public, private-app, and private-data subnets across **2 AZs**
- One Internet Gateway, **one shared NAT Gateway** (cost optimization: single NAT vs one-per-AZ)
- Route tables for each tier with NAT / IGW / isolated routing
- EKS subnet tags (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`, `kubernetes.io/cluster/<name>`)
- VPC Flow Logs to CloudWatch with **7-day** retention
- **Gateway** VPC endpoints for S3 and DynamoDB (free)
- Optional interface endpoints for ECR API/DKR + STS (`enable_interface_endpoints = true`)
- Security groups: `public_alb`, `internal_alb`, `eks_nodes`, `rds`, `redis`, `vpn`, `lambda`

## Usage

```hcl
module "networking" {
  source = "../../modules/networking"

  name_prefix               = "shopcloud-primary"
  vpc_cidr                  = "10.0.0.0/16"
  availability_zones        = ["us-east-1a", "us-east-1b"]
  public_subnet_cidrs       = ["10.0.1.0/24",  "10.0.2.0/24"]
  private_app_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24"]
  private_data_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]
  eks_cluster_name          = "shopcloud-primary"
  vpn_client_cidr           = "10.0.100.0/22"

  tags = {
    Project     = "ShopCloud"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## Outputs

| Name | Purpose |
|---|---|
| `vpc_id`, `vpc_cidr` | For peering, endpoints, SG rules |
| `public_subnet_ids`, `private_app_subnet_ids`, `private_data_subnet_ids` | Feeds ALB, EKS, RDS, Redis |
| `security_group_ids` | Map with keys `public_alb`, `internal_alb`, `eks_nodes`, `rds`, `redis`, `vpn`, `lambda` |
| `public_route_table_id`, `private_app_route_table_id`, `private_data_route_table_id` | For VPC peering routes |

## Cost notes

- Single NAT GW saves ~$32/mo vs a second NAT (and ~$65/mo vs 3-AZ).
- Interface endpoints are off by default — turn them on only if NAT egress to AWS APIs is a problem.
- Flow logs shipped to CloudWatch at 7-day retention keep log storage well inside free tier (5 GB/mo).
