<#
.SYNOPSIS
    Shared helper: read environment-specific values straight from Terraform
    outputs, so every install script agrees with the actual applied state on
    cluster name, account ID, VPC ID, and IRSA role ARNs.

.DESCRIPTION
    Every install-*.ps1 script used to default -ClusterName to
    "shopcloud-primary" and reconstruct role ARNs by hand
    ("$ClusterName-irsa-<addon>"). Pointed at any other environment
    without overriding every parameter, that silently wired add-ons to
    the wrong cluster and a role ARN that doesn't exist there.

    This helper removes the guesswork: it reads eks_cluster_name,
    eks_irsa_role_arns, vpc_id, and aws_account_id directly from
    `terraform output` for the named environment, and refuses to
    proceed if your current AWS credentials don't match that
    environment's account.
#>

function Get-ShopCloudEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("dev-us-east-1", "primary-us-east-1", "dr-eu-west-1")]
        [string] $Environment
    )

    $repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
    $tfDir = Join-Path $repoRoot "terraform\environments\$Environment"

    if (-not (Test-Path $tfDir)) {
        throw "Terraform environment directory not found: $tfDir"
    }

    $accountId = terraform "-chdir=$tfDir" output -raw aws_account_id 2>$null
    if (-not $accountId) {
        throw "Could not read the 'aws_account_id' output from $tfDir. Has 'terraform apply' been run there yet?"
    }

    $callerAccountId = aws sts get-caller-identity --query Account --output text
    if (-not $callerAccountId) {
        throw "Could not determine the currently authenticated AWS account (aws sts get-caller-identity failed)."
    }
    if ($callerAccountId -ne $accountId) {
        throw "Authenticated AWS account ($callerAccountId) does not match the $Environment Terraform state's account ($accountId). Check your AWS credentials before continuing."
    }

    $clusterName = terraform "-chdir=$tfDir" output -raw eks_cluster_name
    $vpcId = terraform "-chdir=$tfDir" output -raw vpc_id
    $irsaRoleArns = terraform "-chdir=$tfDir" output -json eks_irsa_role_arns | ConvertFrom-Json

    [PSCustomObject]@{
        Environment  = $Environment
        AccountId    = $accountId
        ClusterName  = $clusterName
        VpcId        = $vpcId
        IrsaRoleArns = $irsaRoleArns
    }
}

function Get-ShopCloudIrsaRoleArn {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $ShopCloudEnvironment,
        [Parameter(Mandatory = $true)]
        [string] $AddonKey
    )

    $roleArn = $ShopCloudEnvironment.IrsaRoleArns.$AddonKey
    if (-not $roleArn) {
        throw "No '$AddonKey' entry in the eks_irsa_role_arns output for $($ShopCloudEnvironment.Environment). Check terraform/environments/$($ShopCloudEnvironment.Environment)/phase3_compute.tf's irsa_service_accounts map."
    }
    return $roleArn
}
