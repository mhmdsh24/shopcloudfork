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

   For the AWS Load Balancer Controller, use the helper script so Helm gets the
   real EKS VPC ID and IRSA role ARN instead of applying placeholder values:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-aws-lb-controller.ps1
   ```

   In GitHub Actions, expose the repository secret as `AWS_ACCOUNT_ID`; the
   script will use it and verify it matches the assumed AWS role.

   External Secrets also needs its IRSA role rendered before Helm applies:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-external-secrets.ps1
   ```

   Cluster Autoscaler uses the same secret-driven IRSA rendering:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-cluster-autoscaler.ps1
   ```
3. Apply app manifests:
   - production: `kubectl apply -k k8s/overlays/us-east-1`
   - development: `kubectl apply -k k8s/overlays/dev-us-east-1`

## CI/CD

- Production workflows trigger from `main`
- Development workflows trigger from `dev`
- Workflows are split for build/push and EKS deployment by environment

## Domain-dependent features

CloudFront CDN + WAF + Shield, Route 53 latency-based routing with a custom domain, Client VPN with MFA, and ACM certificates are implemented in Terraform modules.

These are disabled in the default `terraform/environments/primary-us-east-1/terraform.tfvars` because they require a registered domain delegated to Route 53 and valid DNS ownership.

SES invoice email also depends on domain ownership. The invoice Lambda writes
PDFs to S3 and sends the PDF as an SES attachment, but AWS will reject outbound
mail until the sender identity is verified. In sandbox mode, SES also requires
each recipient address to be verified; request production access before sending
to arbitrary customer emails. Terraform outputs the SES TXT verification token
and DKIM CNAME tokens as `ses_domain_verification_token` and `ses_dkim_tokens`.

To enable the full production domain stack:

1. Register a domain and delegate its NS records to Route 53.
2. Set `domain_name` in `terraform/environments/primary-us-east-1/terraform.tfvars`.
3. Set `enable_domain = true`, `enable_cloudfront = true`, and `enable_vpn = true`.
4. Apply Terraform again.

The full reference values are provided in `terraform/environments/primary-us-east-1/terraform.tfvars.prod-full-spec`.
