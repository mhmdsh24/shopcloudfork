# ShopCloud

ShopCloud is an AWS EKS-based e-commerce stack with exactly five services:
`catalog`, `cart`, `checkout`, `auth`, `admin`.

## Current Architecture

- Primary environment: `terraform/environments/primary-us-east-1`
- Development environment: `terraform/environments/dev-us-east-1`
- Kubernetes overlays:
  - production: `k8s/overlays/us-east-1`
  - development: `k8s/overlays/dev-us-east-1`
- Invoice pipeline: `checkout -> SQS -> Lambda -> S3 + SES`
- Edge path: Route 53 latency records + CloudFront + WAF + Shield Standard
- Admin path: Client VPN + internal ALB ingress
- Data layer: RDS PostgreSQL (Multi-AZ in prod + cross-region replica enabled) and Redis (Multi-AZ)

## Deploy (High Level)

1. Apply infrastructure:
   - `terraform/environments/primary-us-east-1`
   - `terraform/environments/dev-us-east-1`
2. Install cluster add-ons:
   - AWS Load Balancer Controller
   - External Secrets
   - Metrics Server
   - Cluster Autoscaler
   - KEDA
3. Apply app manifests:
   - production: `kubectl apply -k k8s/overlays/us-east-1`
   - development: `kubectl apply -k k8s/overlays/dev-us-east-1`

## CI/CD

- Production workflows trigger from `main`
- Development workflows trigger from `dev`
- Workflows are split for build/push and EKS deployment by environment
