<#
.SYNOPSIS
    Install or upgrade Cluster Autoscaler using values read straight from
    Terraform state for the named environment.

.DESCRIPTION
    Cluster name and the IRSA role ARN both come from `terraform output`
    for -Environment, not from a hardcoded default. This makes it
    impossible to silently point the autoscaler at the wrong cluster.

.EXAMPLE
    powershell -File scripts\install-cluster-autoscaler.ps1 -Environment dev-us-east-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev-us-east-1", "primary-us-east-1", "dr-eu-west-1")]
    [string] $Environment,
    [string] $ReleaseName = "cluster-autoscaler",
    [string] $Namespace = "kube-system",
    [string] $ValuesFile = "k8s/helm-values/cluster-autoscaler.yaml"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\tf-outputs.ps1"

$shopcloud = Get-ShopCloudEnvironment -Environment $Environment
$RoleArn = Get-ShopCloudIrsaRoleArn -ShopCloudEnvironment $shopcloud -AddonKey "cluster-autoscaler"

Write-Host "=== Cluster Autoscaler ==="
Write-Host "  Environment : $Environment"
Write-Host "  Cluster     : $($shopcloud.ClusterName)"
Write-Host "  Role        : $RoleArn"
Write-Host ""

helm repo add autoscaler https://kubernetes.github.io/autoscaler | Out-Null
helm repo update autoscaler | Out-Null

helm upgrade --install $ReleaseName autoscaler/cluster-autoscaler `
    -n $Namespace `
    -f $ValuesFile `
    --set-string "autoDiscovery.clusterName=$($shopcloud.ClusterName)" `
    --set-string "rbac.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn"

Write-Host ""
Write-Host "Restarting Cluster Autoscaler pod so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName-aws-cluster-autoscaler"

Write-Host ""
Write-Host "Waiting for Cluster Autoscaler rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName-aws-cluster-autoscaler"
