#!/usr/bin/env bash
#
# teardown.sh — destroy all ShopCloud infrastructure to stop billing.
#
# Runs `terraform destroy` in reverse dependency order:
#   1. terraform/global              (peering — no other deps)
#   2. terraform/environments/dr-eu-west-1
#   3. terraform/environments/primary-us-east-1
#
# State bucket + DynamoDB lock table are LEFT IN PLACE intentionally
# — those are cheap (~$0) and you need them to re-apply later.
# Delete them manually via AWS console if you truly want zero footprint.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

echo "==================================================="
echo "  ShopCloud TEARDOWN"
echo "  This will destroy ALL regional infrastructure."
echo "  State bucket + lock table are preserved."
echo "==================================================="
echo
read -r -p "Type 'destroy' to confirm: " CONFIRM
if [ "${CONFIRM}" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# ---------- 1. Global (peering) ----------
if [ -d "terraform/global" ] && [ -f "terraform/global/main.tf" ]; then
  echo
  echo "[1/3] Destroying terraform/global ..."
  (cd terraform/global && terraform init -input=false && terraform destroy -auto-approve)
fi

# ---------- 2. DR region ----------
if [ -d "terraform/environments/dr-eu-west-1" ]; then
  echo
  echo "[2/3] Destroying terraform/environments/dr-eu-west-1 ..."
  (cd terraform/environments/dr-eu-west-1 && terraform init -input=false && terraform destroy -auto-approve)
fi

# ---------- 3. Primary region ----------
if [ -d "terraform/environments/primary-us-east-1" ]; then
  echo
  echo "[3/3] Destroying terraform/environments/primary-us-east-1 ..."
  (cd terraform/environments/primary-us-east-1 && terraform init -input=false && terraform destroy -auto-approve)
fi

echo
echo "==================================================="
echo "  Teardown complete. Ongoing cost: ~\$0/month."
echo "  (Except: Route 53 hosted zones if created — \$0.50/mo each.)"
echo "==================================================="
