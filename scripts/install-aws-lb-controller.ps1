<#
.SYNOPSIS
    Install or upgrade the AWS Load Balancer Controller with rendered AWS values.

.DESCRIPTION
    The Helm values file keeps account and VPC values as placeholders. This
    helper uses AWS_ACCOUNT_ID from the environment when present, verifies it
    against the configured AWS credentials, resolves the EKS VPC ID, then
    passes both values with --set so the controller can start without relying
    on EC2 metadata from inside a pod.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-aws-lb-controller.ps1

.EXAMPLE
    $env:AWS_ACCOUNT_ID = "123456789012"
    powershell -ExecutionPolicy Bypass -File scripts\install-aws-lb-controller.ps1
#>
[CmdletBinding()]
param(
    [string] $ClusterName = "shopcloud-primary",
    [string] $Region = $env:AWS_REGION,
    [string] $AccountId = $env:AWS_ACCOUNT_ID,
    [string] $ReleaseName = "aws-load-balancer-controller",
    [string] $Namespace = "kube-system",
    [string] $ValuesFile = "k8s/helm-values/aws-lb-controller.yaml",
    [string] $RoleName
)

$ErrorActionPreference = "Stop"

if (-not $Region) {
    $Region = "us-east-1"
}

if (-not $RoleName) {
    $RoleName = "$ClusterName-irsa-aws-lb-controller"
}

$CallerAccountId = aws sts get-caller-identity --query Account --output text

if (-not $AccountId) {
    $AccountId = $CallerAccountId
}

if (-not $AccountId) {
    throw "Could not determine AWS account ID from AWS_ACCOUNT_ID or aws sts get-caller-identity."
}

if ($CallerAccountId -and $CallerAccountId -ne $AccountId) {
    throw "AWS_ACCOUNT_ID '$AccountId' does not match the authenticated AWS account '$CallerAccountId'."
}

$VpcId = aws eks describe-cluster `
    --name $ClusterName `
    --region $Region `
    --query "cluster.resourcesVpcConfig.vpcId" `
    --output text

if (-not $VpcId -or $VpcId -eq "None") {
    throw "Could not determine VPC ID for EKS cluster '$ClusterName' in '$Region'."
}

$RoleArn = "arn:aws:iam::${AccountId}:role/$RoleName"

Write-Host "=== AWS Load Balancer Controller ==="
Write-Host "  Cluster : $ClusterName"
Write-Host "  Region  : $Region"
Write-Host "  VPC     : $VpcId"
Write-Host "  Role    : $RoleArn"
Write-Host ""

helm repo add eks https://aws.github.io/eks-charts | Out-Null
helm repo update eks | Out-Null

helm upgrade --install $ReleaseName eks/aws-load-balancer-controller `
    -n $Namespace `
    --create-namespace `
    -f $ValuesFile `
    --set-string "vpcId=$VpcId" `
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn"

Write-Host ""
Write-Host "Restarting controller pods so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName"

Write-Host ""
Write-Host "Waiting for controller rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName"
