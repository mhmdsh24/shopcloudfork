# Module: `peering`

Creates a **cross-region VPC peering connection** between two VPCs in the same AWS account and installs the symmetric routes on both sides. VPC peering itself is free — you pay only for cross-region data transfer.

## Providers

This module requires two aliased `aws` providers:

| Alias | Purpose |
|---|---|
| `aws.requester` | Provider for the requester VPC's region (primary) |
| `aws.accepter`  | Provider for the accepter VPC's region (DR) |

## Usage

```hcl
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-west-1"
}

module "peering" {
  source = "../modules/peering"

  providers = {
    aws.requester = aws.primary
    aws.accepter  = aws.dr
  }

  name                      = "shopcloud-primary-to-dr"
  requester_vpc_id          = data.terraform_remote_state.primary.outputs.vpc_id
  requester_vpc_cidr        = data.terraform_remote_state.primary.outputs.vpc_cidr
  requester_route_table_ids = [
    data.terraform_remote_state.primary.outputs.public_route_table_id,
    data.terraform_remote_state.primary.outputs.private_app_route_table_id,
    data.terraform_remote_state.primary.outputs.private_data_route_table_id,
  ]

  accepter_vpc_id   = data.terraform_remote_state.dr.outputs.vpc_id
  accepter_vpc_cidr = data.terraform_remote_state.dr.outputs.vpc_cidr
  accepter_region   = "eu-west-1"
  accepter_route_table_ids = [
    data.terraform_remote_state.dr.outputs.public_route_table_id,
    data.terraform_remote_state.dr.outputs.private_app_route_table_id,
    data.terraform_remote_state.dr.outputs.private_data_route_table_id,
  ]
}
```
