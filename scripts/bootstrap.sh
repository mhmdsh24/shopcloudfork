#!/usr/bin/env bash
#
# bootstrap.sh — one-time creation of the Terraform remote-state resources.
#
# Creates (if missing):
#   * S3 bucket  : shopcloud-tfstate-<account-id>       (versioned, encrypted, block-public-access)
#   * DynamoDB tbl: shopcloud-terraform-locks            (PAY_PER_REQUEST, LockID key)
#
# Safe to re-run — uses aws CLI idempotent operations.
#
# Requirements: aws cli v2, jq, credentials with S3/DynamoDB create permissions.
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-781863099565}"
BUCKET="shopcloud-tfstate-${ACCOUNT_ID}"
TABLE="shopcloud-terraform-locks"

echo "=== ShopCloud Terraform state bootstrap ==="
echo "  Region  : ${REGION}"
echo "  Account : ${ACCOUNT_ID}"
echo "  Bucket  : ${BUCKET}"
echo "  Table   : ${TABLE}"
echo

# ---------- S3 bucket ----------
if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "[skip] S3 bucket ${BUCKET} already exists."
else
  echo "[create] S3 bucket ${BUCKET}..."
  if [ "${REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
fi

echo "[ensure] versioning enabled..."
aws s3api put-bucket-versioning --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

echo "[ensure] default encryption (SSE-S3)..."
aws s3api put-bucket-encryption --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
      "BucketKeyEnabled": true
    }]
  }'

echo "[ensure] public access blocked..."
aws s3api put-public-access-block --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---------- DynamoDB lock table ----------
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "[skip] DynamoDB table ${TABLE} already exists."
else
  echo "[create] DynamoDB table ${TABLE}..."
  aws dynamodb create-table \
    --region "${REGION}" \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema           AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=ShopCloud Key=ManagedBy,Value=bootstrap
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
fi

echo
echo "=== Bootstrap complete. Ready for 'terraform init'. ==="
