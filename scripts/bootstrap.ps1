<#
.SYNOPSIS
    Bootstrap Terraform remote-state resources.

.DESCRIPTION
    Creates (if missing) the S3 state bucket and DynamoDB lock table used by
    every `backend "s3"` block in this repo. Safe to re-run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
#>
[CmdletBinding()]
param(
    [string] $Region    = $env:AWS_REGION,
    [string] $AccountId = $env:AWS_ACCOUNT_ID
)

$ErrorActionPreference = 'Stop'

if (-not $Region)    { $Region    = 'us-east-1' }
if (-not $AccountId) { $AccountId = '781863099565' }

$Bucket = "shopcloud-tfstate-$AccountId"
$Table  = 'shopcloud-terraform-locks'

Write-Host "=== ShopCloud Terraform state bootstrap ==="
Write-Host "  Region  : $Region"
Write-Host "  Account : $AccountId"
Write-Host "  Bucket  : $Bucket"
Write-Host "  Table   : $Table"
Write-Host ""

# --- Confirm AWS credentials belong to the expected account ---
$caller = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($caller.Account -ne $AccountId) {
    Write-Error "AWS CLI is authenticated as account $($caller.Account), expected $AccountId."
}
Write-Host "[ok] authenticated as $($caller.Arn)"

# --- S3 bucket ---
$exists = $true
try {
    aws s3api head-bucket --bucket $Bucket --region $Region 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $exists = $false }
} catch { $exists = $false }

if ($exists) {
    Write-Host "[skip] S3 bucket $Bucket already exists."
} else {
    Write-Host "[create] S3 bucket $Bucket..."
    if ($Region -eq 'us-east-1') {
        aws s3api create-bucket --bucket $Bucket --region $Region | Out-Null
    } else {
        aws s3api create-bucket --bucket $Bucket --region $Region `
            --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    }
}

Write-Host "[ensure] versioning enabled..."
aws s3api put-bucket-versioning --bucket $Bucket `
    --versioning-configuration Status=Enabled | Out-Null

Write-Host "[ensure] default encryption (SSE-S3)..."
$enc = @{
    Rules = @(@{
        ApplyServerSideEncryptionByDefault = @{ SSEAlgorithm = 'AES256' }
        BucketKeyEnabled = $true
    })
} | ConvertTo-Json -Compress -Depth 6
$enc | Out-File -Encoding ascii "$env:TEMP\enc.json"
aws s3api put-bucket-encryption --bucket $Bucket `
    --server-side-encryption-configuration "file://$env:TEMP\enc.json" | Out-Null

Write-Host "[ensure] public access blocked..."
aws s3api put-public-access-block --bucket $Bucket `
    --public-access-block-configuration `
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null

# --- DynamoDB lock table ---
$tableExists = $true
try {
    aws dynamodb describe-table --table-name $Table --region $Region 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { $tableExists = $false }
} catch { $tableExists = $false }

if ($tableExists) {
    Write-Host "[skip] DynamoDB table $Table already exists."
} else {
    Write-Host "[create] DynamoDB table $Table..."
    aws dynamodb create-table `
        --region $Region `
        --table-name $Table `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema           AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --tags "Key=Project,Value=ShopCloud" "Key=ManagedBy,Value=bootstrap" | Out-Null
    aws dynamodb wait table-exists --table-name $Table --region $Region
}

Write-Host ""
Write-Host "=== Bootstrap complete. Ready for 'terraform init'. ==="
