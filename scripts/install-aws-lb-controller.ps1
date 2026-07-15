<#
.SYNOPSIS
    Install or upgrade the AWS Load Balancer Controller using values read
    straight from Terraform state for the named environment.

.DESCRIPTION
    Cluster name, VPC ID, and the IRSA role ARN all come from
    `terraform output` for -Environment, not from hardcoded defaults.
    This makes it impossible to silently point the controller at the
    wrong cluster/VPC (the exact bug that previously left every Ingress
    stuck with "couldn't auto-discover subnets... tagged for other
    cluster" because the values file's clusterName defaulted to
    shopcloud-primary regardless of which cluster you were installing
    into).

.EXAMPLE
    powershell -File scripts\install-aws-lb-controller.ps1 -Environment dev-us-east-1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev-us-east-1", "primary-us-east-1", "dr-eu-west-1")]
    [string] $Environment,
    [string] $ReleaseName = "aws-load-balancer-controller",
    [string] $Namespace = "kube-system",
    [string] $ValuesFile = "k8s/helm-values/aws-lb-controller.yaml"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\tf-outputs.ps1"

$shopcloud = Get-ShopCloudEnvironment -Environment $Environment
$RoleArn = Get-ShopCloudIrsaRoleArn -ShopCloudEnvironment $shopcloud -AddonKey "aws-lb-controller"

Write-Host "=== AWS Load Balancer Controller ==="
Write-Host "  Environment : $Environment"
Write-Host "  Cluster     : $($shopcloud.ClusterName)"
Write-Host "  VPC         : $($shopcloud.VpcId)"
Write-Host "  Role        : $RoleArn"
Write-Host ""

helm repo add eks https://aws.github.io/eks-charts | Out-Null
helm repo update eks | Out-Null

helm upgrade --install $ReleaseName eks/aws-load-balancer-controller `
    -n $Namespace `
    --create-namespace `
    -f $ValuesFile `
    --set-string "clusterName=$($shopcloud.ClusterName)" `
    --set-string "vpcId=$($shopcloud.VpcId)" `
    --set-string "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$RoleArn"

Write-Host ""
Write-Host "Restarting controller pods so IRSA env vars are re-injected..."
kubectl -n $Namespace rollout restart "deployment/$ReleaseName"

Write-Host ""
Write-Host "Waiting for controller rollout..."
kubectl -n $Namespace rollout status "deployment/$ReleaseName"
