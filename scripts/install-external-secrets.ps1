<#
.SYNOPSIS
    Install or upgrade External Secrets with the rendered IRSA role ARN.

.DESCRIPTION
    The Helm values file keeps the AWS account ID as a placeholder. This helper
    uses AWS_ACCOUNT_ID from the environment when present, verifies it against
    the configured AWS credentials, and passes the rendered role ARN with --set.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\install-external-secrets.ps1
#>
[CmdletBinding()]
param(
    [string] $ClusterName = "shopcloud-primary",
    [string] $AccountId = $env:AWS_ACCOUNT_ID,
    [string] $ReleaseName = "external-secrets",
    [string] $Namespace = "external-secrets",
    [string] $ValuesFile = "k8s/helm-values/external-secrets.yaml",
    [string] $RoleName
)

$ErrorActionPreference = "Stop"

if (-not $RoleName) {
    $RoleName = "$ClusterName-irsa-external-secrets"
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

Write-Host "=== External Secrets ==="
Write-Host "  Cluster : $ClusterName"
Write-Host "  Role    : $RoleArn"
Write-Host ""

helm repo add external-secrets https://charts.external-secrets.io | Out-Null
helm repo update external-secrets | Out-Null

helm upgrade --install $ReleaseName external-secrets/external-secrets `
    -n $Namespace `
    --create-namespace `
    -f $ValuesFile `
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn"

Write-Host ""
Write-Host "Restarting External Secrets controller so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName"

Write-Host ""
Write-Host "Waiting for External Secrets controller rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName"
