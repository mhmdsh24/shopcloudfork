<#
.SYNOPSIS
    Install or upgrade External Secrets using values read straight from
    Terraform state for the named environment.

.DESCRIPTION
    The IRSA role ARN comes from `terraform output` for -Environment,
    not from a hardcoded default. This makes it impossible to silently
    point the controller at the wrong cluster's role.

.EXAMPLE
    powershell -File scripts\install-external-secrets.ps1 -Environment dev-us-east-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev-us-east-1", "primary-us-east-1", "dr-eu-west-1")]
    [string] $Environment,
    [string] $ReleaseName = "external-secrets",
    [string] $Namespace = "external-secrets",
    [string] $ValuesFile = "k8s/helm-values/external-secrets.yaml"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\tf-outputs.ps1"

$shopcloud = Get-ShopCloudEnvironment -Environment $Environment
$RoleArn = Get-ShopCloudIrsaRoleArn -ShopCloudEnvironment $shopcloud -AddonKey "external-secrets"

Write-Host "=== External Secrets ==="
Write-Host "  Environment : $Environment"
Write-Host "  Cluster     : $($shopcloud.ClusterName)"
Write-Host "  Role        : $RoleArn"
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
