<#
.SYNOPSIS
    Install or upgrade Cluster Autoscaler with the rendered IRSA role ARN.

.DESCRIPTION
    The Helm values file keeps the AWS account ID as a placeholder. This helper
    uses AWS_ACCOUNT_ID from the environment when present, verifies it against
    the configured AWS credentials, and passes the rendered role ARN with --set.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-cluster-autoscaler.ps1
#>
[CmdletBinding()]
param(
    [string] $ClusterName = "shopcloud-primary",
    [string] $AccountId = $env:AWS_ACCOUNT_ID,
    [string] $ReleaseName = "cluster-autoscaler",
    [string] $Namespace = "kube-system",
    [string] $ValuesFile = "k8s/helm-values/cluster-autoscaler.yaml",
    [string] $RoleName
)

$ErrorActionPreference = "Stop"

if (-not $RoleName) {
    $RoleName = "$ClusterName-irsa-cluster-autoscaler"
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

$RoleArn = "arn:aws:iam::${AccountId}:role/$RoleName"

Write-Host "=== Cluster Autoscaler ==="
Write-Host "  Cluster : $ClusterName"
Write-Host "  Role    : $RoleArn"
Write-Host ""

helm repo add autoscaler https://kubernetes.github.io/autoscaler | Out-Null
helm repo update autoscaler | Out-Null

helm upgrade --install $ReleaseName autoscaler/cluster-autoscaler `
    -n $Namespace `
    -f $ValuesFile `
    --set-string "autoDiscovery.clusterName=$ClusterName" `
    --set-string "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn"

Write-Host ""
Write-Host "Restarting Cluster Autoscaler pod so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName-aws-cluster-autoscaler"

Write-Host ""
Write-Host "Waiting for Cluster Autoscaler rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName-aws-cluster-autoscaler"
