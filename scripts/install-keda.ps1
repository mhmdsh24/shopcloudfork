<#
.SYNOPSIS
    Install or upgrade KEDA using values read straight from Terraform
    state for the named environment.

.DESCRIPTION
    The IRSA role ARN comes from `terraform output` for -Environment,
    not from a hardcoded default.

.EXAMPLE
    powershell -File scripts\install-keda.ps1 -Environment dev-us-east-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev-us-east-1", "primary-us-east-1", "dr-eu-west-1")]
    [string] $Environment,
    [string] $ReleaseName = "keda",
    [string] $Namespace = "keda",
    [string] $ValuesFile = "k8s/helm-values/keda.yaml"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\tf-outputs.ps1"

$shopcloud = Get-ShopCloudEnvironment -Environment $Environment
$RoleArn = Get-ShopCloudIrsaRoleArn -ShopCloudEnvironment $shopcloud -AddonKey "keda"

Write-Host "=== KEDA ==="
Write-Host "  Environment : $Environment"
Write-Host "  Cluster     : $($shopcloud.ClusterName)"
Write-Host "  Role        : $RoleArn"
Write-Host ""

helm repo add kedacore https://kedacore.github.io/charts | Out-Null
helm repo update kedacore | Out-Null

helm upgrade --install $ReleaseName kedacore/keda `
    -n $Namespace `
    --create-namespace `
    -f $ValuesFile `
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn" `
    --set-string "podIdentity.aws.irsa.roleArn=$RoleArn"

Write-Host ""
Write-Host "Restarting KEDA operator so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName-operator"

Write-Host ""
Write-Host "Waiting for KEDA operator rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName-operator"
