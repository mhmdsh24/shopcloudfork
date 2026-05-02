# ShopCloud

ShopCloud is an AWS-hosted e-commerce platform built on EKS. The application is split into five services:

- `catalog`: product browsing, search, categories, and the storefront page
- `cart`: low-latency shopping cart/session state
- `checkout`: order creation and invoice event publishing
- `auth`: customer authentication through Amazon Cognito, plus legacy admin Cognito helpers
- `admin`: private administrative interface with DB-backed email/password admin sessions

The production customer domain is `shopcloud-503q.click`.

## Architecture

ShopCloud uses a primary production region in `us-east-1`, a DR environment in `eu-west-1`, and a separate development environment.

```text
Customer
  -> Route 53 public hosted zone
  -> CloudFront custom domain, TLS, caching, WAF
  -> Route 53 latency aliases for origin.shopcloud-503q.click
  -> nearest healthy public Application Load Balancer in us-east-1 or eu-west-1
  -> AWS Load Balancer Controller ingress
  -> EKS services: catalog, cart, checkout, auth

Admin
  -> AWS Client VPN
  -> Route 53 private hosted zone
  -> Internal Application Load Balancer
  -> AWS Load Balancer Controller ingress
  -> EKS service: admin

Checkout invoice flow
  -> checkout service
  -> Amazon SQS invoice queue
  -> AWS Lambda PDF generator
  -> S3 invoice bucket
  -> Amazon SES email with PDF attachment

Cart/session flow
  -> cart service
  -> Amazon ElastiCache for Redis, Multi-AZ

Product/order data flow
  -> catalog and checkout services
  -> Amazon RDS PostgreSQL, Multi-AZ in production
```

## Environments

| Environment | Region | Purpose | Terraform path | Kubernetes overlay |
| --- | --- | --- | --- | --- |
| Production primary | `us-east-1` | Live customer/admin workload | `terraform/environments/primary-us-east-1` | `k8s/overlays/us-east-1` |
| Development | `us-east-1` | CI/CD dev deploys and testing | `terraform/environments/dev-us-east-1` | `k8s/overlays/dev-us-east-1` |
| Disaster recovery | `eu-west-1` | Warm DR cluster and regional ingress | `terraform/environments/dr-eu-west-1` | `k8s/overlays/eu-west-1` |
| Global | Cross-region | Peering/global supporting resources | `terraform/global` | n/a |

Production uses:

- EKS cluster: `shopcloud-primary`
- Public customer hostnames: `https://shopcloud-503q.click` and `https://app.shopcloud-503q.click`
- CloudFront origin hostname: `origin.shopcloud-503q.click`
- Private admin hostname: `admin.internal.shopcloud-503q.click`
- Public US ALB: `k8s-shopcloudpublic-afbeb03e50-1960809462.us-east-1.elb.amazonaws.com`
- Public EU ALB: `k8s-shopcloudpublic-dca989f5cd-486176209.eu-west-1.elb.amazonaws.com`
- CloudFront distribution: `E3SWU5X2NYGI9E`
- Public hosted zone: `Z03870742KSFCPI8PJWDC`
- Private hosted zone: `Z03072971G44YK6HA4NV6`

## Customer Path

Customers enter through CloudFront. CloudFront resolves its custom origin through Route 53 latency-based routing.

```text
Customer browser
  -> Route 53 A alias for shopcloud-503q.click or app.shopcloud-503q.click
  -> CloudFront distribution d3rr231e93c53u.cloudfront.net
  -> AWS WAF web ACL on CloudFront
  -> CloudFront origin origin.shopcloud-503q.click
  -> Route 53 latency alias to US public ALB k8s-shopcloudpublic-afbeb03e50-1960809462.us-east-1.elb.amazonaws.com
     or EU public ALB k8s-shopcloudpublic-dca989f5cd-486176209.eu-west-1.elb.amazonaws.com
  -> EKS ingress shopcloud-public
  -> Service by path
```

Ingress routing:

| Public path | Backend service | Purpose |
| --- | --- | --- |
| `/` | `catalog` | Storefront HTML |
| `/api/catalog/*` | `catalog` | Products, categories, search |
| `/api/cart/*` | `cart` | Cart/session API |
| `/api/checkout/*` | `checkout` | Checkout and order creation |
| `/api/auth/*` | `auth` | Customer signup/login API and legacy auth helpers |

Route 53 publishes public apex/app aliases to CloudFront, then publishes one `origin.shopcloud-503q.click` latency record for the US ALB and one for the EU ALB. Both origin aliases enable ALB target-health evaluation, so Route 53 answers CloudFront origin DNS lookups with the lowest-latency healthy region and removes an unhealthy regional ALB from DNS answers. When both ALB endpoints and CloudFront are configured, Terraform output `public_routing_mode` is `cloudfront-regional-origin-latency`.

CloudFront terminates viewer TLS, applies WAF, and keeps the customer hostnames stable while Route 53 chooses the regional origin behind CloudFront. If HTTPS is required from CloudFront to the ALBs, attach regional ACM certificates to the Kubernetes ingresses and set the CloudFront origin protocol policy to HTTPS.

Shield Standard automatically protects Route 53, ALB, and CloudFront when CloudFront is enabled. Shield Advanced is not enabled.

## Admin Path

Administrative traffic does not use the public customer front door.

```text
Admin user
  -> AWS Client VPN
  -> VPC private DNS resolver
  -> Route 53 private hosted zone internal.shopcloud-503q.click
  -> admin.internal.shopcloud-503q.click
  -> Internal ALB internal-k8s-shopcloudadmin-0a74081895-332932850.us-east-1.elb.amazonaws.com
  -> EKS ingress shopcloud-admin
  -> admin service
```

The public hosted zone does not publish an `admin.internal.shopcloud-503q.click` A record. The name exists only in the private hosted zone associated with the VPC.

Client VPN is currently certificate-authenticated with mutual TLS. The Terraform VPN module supports MFA by setting `vpn_mfa_saml_provider_arn`, but the live endpoint is certificate-only until an IAM SAML provider with MFA is configured.

The admin service provides email/password signup and login on the private admin host, then uses a secure session cookie for admin API calls. The dashboard supports product management and read-only order review.

## Service Connections

| Service | External AWS dependencies | Notes |
| --- | --- | --- |
| `catalog` | RDS PostgreSQL, Secrets Manager | Reads product data from the database. Initializes schema in writable environments. |
| `cart` | ElastiCache Redis, Secrets Manager | Stores low-latency cart/session state in Redis. |
| `checkout` | RDS PostgreSQL, Redis, SQS, Secrets Manager | Creates orders, optionally reads cart/session data, and publishes invoice events. |
| `auth` | Cognito, Secrets Manager | Uses Cognito customer/admin user pools for auth service endpoints. |
| `admin` | RDS PostgreSQL, Secrets Manager | Private operational view for staff; stores admin accounts and reads/writes product data in PostgreSQL. |
| Invoice Lambda | SQS, S3, SES, CloudWatch Logs | Generates PDF invoices, stores them in S3, and sends email through SES. |

Secrets are synchronized into Kubernetes through External Secrets Operator. Service accounts use IRSA roles, so pods receive scoped IAM permissions without static AWS keys.

## Data Layer

Production data services:

- RDS PostgreSQL for product/order/admin data
- RDS Multi-AZ enabled in production
- Cross-region RDS read replica enabled for DR
- ElastiCache for Redis with Multi-AZ for carts and session state
- S3 invoice bucket with public access blocked and encryption enabled
- SQS invoice queue with a DLQ
- SES domain/email identities for invoice delivery

Important DR note: the DR database is a read replica. Catalog reads work in DR, but checkout writes should not be routed there until the data layer is changed to a writable regional database, a promoted failover database, or another write-safe replication design.

## Checkout And Invoice Flow

```text
1. Customer submits checkout in the frontend.
2. Frontend calls /api/checkout through CloudFront and the Route 53-selected regional origin.
3. checkout validates the request and writes the order to PostgreSQL.
4. checkout publishes an invoice event to SQS.
5. SQS triggers the invoice Lambda.
6. Lambda renders a PDF invoice.
7. Lambda uploads the PDF to S3.
8. Lambda sends the invoice email through SES.
```

KEDA is included for SQS-based scaling so consumers can scale with invoice queue depth when traffic bursts.

SES caveat: if the AWS account is still in SES sandbox mode, both the sender and recipient identities must be verified. Production SES access is required before sending invoices to arbitrary customer emails.

## Security Implementations

Network and edge security:

- Route 53 public zone for customer records
- CloudFront/WAF customer front door
- Route 53 latency records for `origin.shopcloud-503q.click` across US/EU public ALBs with ALB target-health evaluation
- Route 53 private zone for admin DNS
- Shield Standard through AWS managed protection
- Public ALB only for customer traffic
- Internal ALB for admin traffic
- Client VPN for private admin access
- Security groups restrict access between ALBs, EKS nodes, RDS, Redis, Lambda, and VPN

Identity and access:

- GitHub Actions uses OIDC to assume AWS IAM roles
- No long-lived AWS access keys are required in GitHub
- Required GitHub secret: `AWS_ACCOUNT_ID`
- EKS pods use IRSA for service-specific AWS permissions
- External Secrets Operator reads only the secrets it needs through IAM
- Customer authentication uses Cognito; admin access is private-network scoped and uses the admin service's email/password sessions

Application and Kubernetes hardening:

- Containers run as non-root user `1000`
- Read-only root filesystem is enabled in Kubernetes manifests
- Linux capabilities are dropped
- Privilege escalation is disabled
- Runtime default seccomp profile is configured
- Pod Security admission labels are set to `restricted`
- Liveness and readiness probes are defined
- Rolling updates use `maxUnavailable: 0`
- Pod disruption budgets and HPAs are configured

Data protection and observability:

- RDS SSL is enforced through the parameter group
- Redis auth token is stored in Secrets Manager
- Secrets Manager can use a customer-managed KMS key
- S3 invoice bucket blocks public access
- VPC flow logs are enabled
- Client VPN connection logs are enabled
- Lambda logs go to CloudWatch
- Terraform state uses the configured remote backend and locking

## CI/CD

The project follows the CI/CD pattern from the lab:

```text
Pull request
  -> CI checks
  -> review and merge

dev branch
  -> build images
  -> Trivy scan
  -> push to ECR
  -> automatic deploy to shopcloud-dev

main branch
  -> build images
  -> Trivy scan
  -> push to ECR
  -> wait for production environment approval
  -> deploy exact commit SHA to shopcloud-primary

Terraform PR
  -> fmt
  -> init
  -> validate
  -> plan
  -> PR comment with plan output

Terraform merge to main
  -> production environment approval
  -> terraform apply
```

Workflows:

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `.github/workflows/ci.yml` | PRs to `dev` or `main`, selected pushes, manual | Python compile, Kustomize render, Docker build, Trivy scan, Terraform fmt |
| `.github/workflows/docker-build-push-dev.yml` | Push to `dev`, manual | Build, scan, and push `dev-latest` plus commit SHA images |
| `.github/workflows/k8s-deploy-dev.yml` | Successful dev image build, manual | Deploy the exact built SHA to `shopcloud-dev` |
| `.github/workflows/docker-build-push.yml` | Push to `main`, manual | Build, scan, and push `prod-latest` plus commit SHA images |
| `.github/workflows/k8s-deploy.yml` | Successful prod image build, manual | Deploy the exact built SHA to `shopcloud-primary` after production approval |
| `.github/workflows/terraform-plan.yml` | Terraform PR changes | Validate and comment Terraform plans |
| `.github/workflows/terraform-apply.yml` | Push to `main`, manual | Apply Terraform with production environment protection |

Recommended GitHub repository settings:

- Protect `main`
- Require pull requests before merging
- Require CI/Terraform checks to pass
- Require branches to be up to date before merging
- Configure the GitHub `production` Environment with required reviewers
- Do not store AWS access keys in GitHub secrets; use OIDC roles

## Deployment

High-level deployment order:

1. Apply Terraform for the target environment.
2. Install cluster add-ons.
3. Apply Kubernetes manifests.
4. Let CI/CD manage image rollout after that.

Kubernetes upgrade notes:

- Terraform targets EKS Kubernetes `1.35` for primary, development, and DR.
- For an existing cluster that is still on `1.30`, do not apply directly to `1.35`. EKS minor upgrades must be performed one minor at a time. Apply `-var eks_cluster_version=1.31`, then `1.32`, `1.33`, `1.34`, and finally `1.35`.
- Kubernetes `1.35` expects nodes to run without cgroup v1 by default. The EKS module explicitly uses the `AL2023_x86_64_STANDARD` managed node AMI type so new workers use cgroup v2.
- Review the Terraform plan before applying. Moving an existing managed node group from an older AMI family to AL2023 may replace or roll the node group, so keep enough capacity for PodDisruptionBudgets and system pods.
- Re-run the Helm add-on scripts after the control plane and nodes are on the target minor. The Cluster Autoscaler values pin the 1.35 image, and Terraform resolves compatible EKS-managed `vpc-cni`, `coredns`, and `kube-proxy` add-on versions.

Cluster add-ons:

- AWS Load Balancer Controller
- External Secrets Operator
- Metrics Server
- Cluster Autoscaler
- KEDA

Helper scripts render the real AWS account ID, VPC ID, and IRSA role ARN before installing Helm charts:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-aws-lb-controller.ps1
powershell -ExecutionPolicy Bypass -File scripts\install-external-secrets.ps1
powershell -ExecutionPolicy Bypass -File scripts\install-cluster-autoscaler.ps1
```

Manual app manifest apply, when needed:

```powershell
kubectl apply -k k8s/overlays/us-east-1
kubectl apply -k k8s/overlays/dev-us-east-1
kubectl apply -k k8s/overlays/eu-west-1
```

In normal operation, prefer GitHub Actions over manual `kubectl set image` so every deployment uses the same build, scan, push, and rollout path.

## Disaster Recovery

The DR environment in `eu-west-1` has:

- EKS cluster `shopcloud-dr`
- Public ALB `k8s-shopcloudpublic-dca989f5cd-486176209.eu-west-1.elb.amazonaws.com`
- Internal ALB `internal-k8s-shopcloudadmin-ec43e1bc35-461599104.eu-west-1.elb.amazonaws.com`
- External Secrets configured for DR secrets
- Service account patches for `shopcloud-dr-irsa-*`
- Image patches for ECR in `eu-west-1`
- `SKIP_DB_SCHEMA_INIT=true` for catalog, checkout, and admin because the DR database is a read replica

Before using the EU ALB for live checkout traffic, promote or provide a write-capable DR database. The current EU database is a read replica, so checkout POSTs routed to EU will fail until the write strategy is solved.

## Known Constraints

- CloudFront origin selection depends on DNS resolution of `origin.shopcloud-503q.click`; Route 53 health/ALB health determines which regional origin is returned.
- CloudFront origin groups are not used because they cannot be used on a cache behavior that allows write methods.
- Client VPN MFA is supported by Terraform but not active until `vpn_mfa_saml_provider_arn` is configured.
- SES may still require verified recipients if the account is in sandbox mode.
- DR checkout writes are not safe while DR uses an RDS read replica.

## Useful Checks

```powershell
terraform -chdir=terraform/environments/primary-us-east-1 validate
terraform -chdir=terraform/environments/primary-us-east-1 plan
terraform -chdir=terraform/environments/primary-us-east-1 output public_routing_mode
terraform -chdir=terraform/environments/primary-us-east-1 output cloudfront_configured_origin

kubectl --context arn:aws:eks:us-east-1:${AWS_ACCOUNT_ID}:cluster/shopcloud-primary -n shopcloud get pods,ingress
kubectl --context shopcloud-dr -n shopcloud get pods,ingress

curl.exe https://shopcloud-503q.click/api/catalog/products
curl.exe https://app.shopcloud-503q.click/api/catalog/products
```

## Repository Map

```text
services/
  admin/
  auth/
  cart/
  catalog/
  checkout/

k8s/
  base/
  overlays/
    us-east-1/
    dev-us-east-1/
    eu-west-1/
  helm-values/
  addons/

terraform/
  environments/
    primary-us-east-1/
    dev-us-east-1/
    dr-eu-west-1/
  global/
  modules/

.github/workflows/
  ci.yml
  docker-build-push.yml
  docker-build-push-dev.yml
  k8s-deploy.yml
  k8s-deploy-dev.yml
  terraform-plan.yml
  terraform-apply.yml
```
