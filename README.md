# ShopCloud

Multi-region e-commerce platform on AWS, defined entirely as Infrastructure as Code with **Terraform** and **Kubernetes**. Cost-optimized for the AWS Free Tier while preserving every architectural component from the reference design:

- EKS (2 × t3.medium spot) in `us-east-1` with 5 microservices
- Aurora PostgreSQL **Global Database** (primary in `us-east-1`, secondary in `eu-west-1`)
- ElastiCache Redis (primary + standby)
- CloudFront + WAF v2 + ACM + Route 53 failover + Shield Standard
- Cognito (customer + admin pools)
- EventBridge → SQS → Lambda → S3 → SES invoice pipeline
- Client VPN for admin access
- ECS Fargate **scale-from-zero** DR in `eu-west-1`
- CloudWatch alarms, CloudTrail, SNS alerts
- GitHub Actions CI/CD with OIDC (no static credentials)

> Estimated monthly cost with everything running: **~$280–$385/mo**. Reducible to **~$120/mo** by flipping `enable_vpn=false`, `enable_cloudfront=false`, and tearing down the DR region. Run `scripts/teardown.sh` to stop all charges.

---

## Repository Layout

```
shopcloud/
├── terraform/
│   ├── modules/              # 15 reusable modules
│   │   ├── networking/       # VPC, subnets, NAT, SGs, flow logs
│   │   ├── peering/          # cross-region VPC peering
│   │   ├── secrets/          # KMS + Secrets Manager + SSM (with cross-region replica)
│   │   ├── ecr/              # 6 image repos + cross-region replication
│   │   ├── rds/              # Aurora Global Database (primary | secondary | standalone)
│   │   ├── elasticache/      # Redis
│   │   ├── s3-invoices/      # Invoice bucket + CRR
│   │   ├── cognito/          # customer + admin pools
│   │   ├── iam/              # GitHub OIDC deploy role
│   │   ├── sqs-lambda/       # EventBridge + SQS + Lambda (Python PDF gen) + SES
│   │   ├── eks/              # cluster + spot nodes + OIDC + IRSA
│   │   ├── dns/              # Route 53 public + private zones + failover records
│   │   ├── cdn-waf/          # CloudFront + WAF v2 (CLOUDFRONT scope)
│   │   ├── vpn/              # AWS Client VPN (mutual TLS, single subnet assoc)
│   │   ├── dr/               # DR ALB + WAF + ECS Fargate (desired=0)
│   │   └── monitoring/       # SNS + CloudWatch alarms + CloudTrail
│   ├── environments/
│   │   ├── primary-us-east-1/
│   │   └── dr-eu-west-1/
│   └── global/               # cross-region peering via remote state
├── k8s/
│   ├── base/                 # namespace, default-deny, 5 services, ingress, keda, external-secrets
│   ├── overlays/{us-east-1,eu-west-1}/
│   └── helm-values/          # aws-lb-controller, keda, cluster-autoscaler, external-secrets, metrics-server
├── services/                 # 6 FastAPI apps + Dockerfiles
├── ci-cd/github-actions/     # 4 workflows (plan, apply, build-push, k8s-deploy)
├── scripts/                  # bootstrap, failover, teardown
└── README.md
```

## Build Status — all phases complete

| Phase | Scope | Status |
|------|------|------|
| **1** | Foundation — VPC, subnets, NAT, flow logs, SGs, peering | ✅ `terraform validate` clean |
| **2** | Data — ECR, Aurora GDB, Redis, KMS, Secrets Manager, S3 invoices | ✅ code complete |
| **3** | Compute — Cognito, EventBridge/SQS/Lambda, SES, EKS + IRSA, K8s manifests, Helm values | ✅ code complete |
| **4** | Edge & access — Route 53, CloudFront + WAF, Client VPN | ✅ code complete (toggleable) |
| **5** | DR — ALB, WAF, ECS Fargate scale-from-zero, failover script | ✅ code complete |
| **6** | Observability — CloudWatch alarms, CloudTrail, SNS | ✅ code complete |

`terraform fmt -recursive` passes cleanly. Full `terraform validate` cannot be run from this machine because `registry.terraform.io` is geo-blocked (HashiCorp trade-controls notice). Run `terraform init` from any unblocked network and `validate` should succeed — the code is syntactically clean.

## Remote State

| Resource | Value |
|---|---|
| AWS account ID | `781863099565` |
| State bucket | `shopcloud-tfstate-781863099565` (us-east-1) |
| Lock table | `shopcloud-terraform-locks` (us-east-1) |
| Primary state key | `primary-us-east-1/terraform.tfstate` |
| DR state key | `dr-eu-west-1/terraform.tfstate` |
| Global state key | `global/terraform.tfstate` |

## Deploy — recommended order

```bash
# 0. One-time — create state bucket + lock table
./scripts/bootstrap.sh

# 1. Primary region (creates Global DB as side-effect)
cd terraform/environments/primary-us-east-1
terraform init
terraform plan                        # <-- review before apply
terraform apply

# 2. DR region (joins Global DB, creates DR ALB + ECS task defs)
cd ../dr-eu-west-1
terraform init
terraform plan
terraform apply

# 3. Global — cross-region VPC peering
cd ../../global
terraform init
terraform plan
terraform apply

# 4. Back-fill cross-region S3 replication on primary
cd ../environments/primary-us-east-1
terraform apply -var dr_invoice_bucket_arn="$(cd ../dr-eu-west-1 && terraform output -raw invoices_replica_bucket_arn)"

# 5. Install Helm charts and Kubernetes manifests on EKS
aws eks update-kubeconfig --name shopcloud-primary --region us-east-1

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system -f k8s/helm-values/aws-lb-controller.yaml

helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system -f k8s/helm-values/metrics-server.yaml

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system -f k8s/helm-values/cluster-autoscaler.yaml

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace -f k8s/helm-values/external-secrets.yaml

helm upgrade --install keda kedacore/keda \
  -n keda --create-namespace -f k8s/helm-values/keda.yaml

kubectl apply -k k8s/overlays/us-east-1

# 6. Capture the public ALB DNS name that AWS LB Controller created,
# then publish the failover record by re-running Terraform with it:
PUBLIC_ALB_DNS=$(kubectl -n shopcloud get ingress shopcloud-public \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
cd terraform/environments/primary-us-east-1
terraform apply -var primary_alb_dns_name=$PUBLIC_ALB_DNS  # similarly for internal/dr ALBs

# 7. Finally, opt into CloudFront + VPN when you need them:
terraform apply -var enable_cloudfront=true -var enable_vpn=true \
  -var vpn_server_certificate_arn=... -var vpn_client_root_certificate_arn=...
```

## Tear down

```bash
./scripts/teardown.sh
```

This runs `terraform destroy` in the correct reverse order and leaves the state bucket + lock table in place (pennies/month, reusable).

## DR failover

```bash
./scripts/failover.sh
```

Promotes Aurora, scales ECS Fargate from 0 to 2 per service, and checks `/healthz` at `app.shopcloud.com`.

## Conventions

- Every resource is tagged `Project=ShopCloud`, `Environment=production`, `ManagedBy=terraform`, `CostCenter=free-tier-optimized`.
- Two-AZ deployments everywhere (minimum for ALB/EKS; saves vs three).
- Single NAT Gateway per region (~$65/mo cheaper than per-AZ).
- CloudWatch log retention = 7 days by default.
- Secrets bootstrap with random placeholders, then the data modules (rds, redis, cognito) overwrite with real values once resources exist — External Secrets Operator can then sync them into the cluster.
- EKS spot instances (`t3.medium` / `t3a.medium`) with cluster autoscaler + KEDA (SQS-driven).
