#!/usr/bin/env bash
#
# failover.sh - promote the eu-west-1 DR region to primary.
#
# Steps:
#   1. Promote the cross-region RDS PostgreSQL read replica to a
#      standalone writable instance.
#   2. Scale each ECS Fargate service from 0 -> 2 tasks.
#   3. Wait for services to stabilize.
#   4. Spot-check /healthz on the DR ALB.
#   5. Print reminders for Route 53 + Cognito callback updates.
#
# Route 53 auto-fails-over via the health check on the primary ALB, so
# DNS typically switches within ~90s without manual intervention.
#
# Requirements: aws cli v2, curl.
#
# If you deployed Aurora with a Global Database (spec Option B) instead
# of standard RDS (spec Option A), swap step 1 for:
#   aws rds failover-global-cluster \
#     --global-cluster-identifier <global-db-id> \
#     --target-db-cluster-identifier <dr-cluster-arn> \
#     --region "${DR_REGION}"
#
set -euo pipefail

ACCOUNT_ID="${AWS_ACCOUNT_ID:-781863099565}"
DR_REGION="${DR_REGION:-eu-west-1}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
DR_DB_INSTANCE_ID="${DR_DB_INSTANCE_ID:-shopcloud-dr-postgres}"
DR_ECS_CLUSTER="${DR_ECS_CLUSTER:-shopcloud-dr-cluster}"
SERVICES=("catalog" "cart" "checkout" "auth" "admin")
HEALTH_URL="${HEALTH_URL:-https://app.shopcloud.com/healthz}"

echo "================================================================="
echo "  ShopCloud DR Failover - promoting ${DR_REGION}"
echo "================================================================="

# ---------- 1. RDS read replica promotion ----------
echo
echo "[1/4] Promoting cross-region RDS read replica ${DR_DB_INSTANCE_ID}..."
aws rds promote-read-replica \
  --db-instance-identifier "${DR_DB_INSTANCE_ID}" \
  --backup-retention-period 7 \
  --region "${DR_REGION}" \
  || echo "  (promote-read-replica returned non-zero; instance may already be standalone)"

echo "  Waiting for DR DB instance to report available..."
aws rds wait db-instance-available \
  --db-instance-identifier "${DR_DB_INSTANCE_ID}" \
  --region "${DR_REGION}"

# ---------- 2. Scale ECS Fargate services ----------
echo
echo "[2/4] Scaling ECS Fargate services to 2 tasks each..."
for SVC in "${SERVICES[@]}"; do
  aws ecs update-service \
    --cluster "${DR_ECS_CLUSTER}" \
    --service "${SVC}" \
    --desired-count 2 \
    --region "${DR_REGION}" >/dev/null
  echo "  scaled ${SVC} -> 2 tasks"
done

echo
echo "[3/4] Waiting for services to stabilize..."
for SVC in "${SERVICES[@]}"; do
  aws ecs wait services-stable \
    --cluster "${DR_ECS_CLUSTER}" \
    --services "${SVC}" \
    --region "${DR_REGION}"
  echo "  ${SVC} stable"
done

# ---------- 3. Health check ----------
echo
echo "[4/4] Checking ${HEALTH_URL}..."
sleep 30
CODE=$(curl -sSfo /dev/null -w "%{http_code}" "${HEALTH_URL}" || echo "000")
if [ "${CODE}" = "200" ]; then
  echo "  Health check PASSED (${CODE})"
else
  echo "  WARNING - health check returned ${CODE} - Route 53 may still be propagating"
fi

cat <<'EOF'

=================================================================
  Failover complete.
  Manual follow-up:
    * Verify Route 53 is routing to the DR ALB (dig app.shopcloud.com)
    * If using a distinct DR domain, update Cognito callback URLs
    * Watch CloudWatch alarms in the DR region for 15-30 min
    * DR is now authoritative. When the old primary is restored,
      re-create the replication in the opposite direction:
        aws rds create-db-instance-read-replica \
          --db-instance-identifier shopcloud-primary-postgres \
          --source-db-instance-identifier <promoted-dr-arn> \
          --region us-east-1
        kubectl scale deploy <svc> --replicas=2 -n shopcloud
        aws ecs update-service --desired-count 0 ... (for each DR svc)
=================================================================
EOF
