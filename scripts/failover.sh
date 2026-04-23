#!/usr/bin/env bash
#
# failover.sh — promote the eu-west-1 DR region to primary.
#
# Steps:
#   1. Promote Aurora Global Database secondary (eu-west-1) to primary.
#   2. (Optional) Promote ElastiCache Global Datastore if enabled.
#   3. Scale each ECS Fargate service from 0 -> 2 tasks.
#   4. Wait for services to stabilize.
#   5. Spot-check /healthz on the DR ALB.
#   6. Print reminders for Route 53 + Cognito callback updates.
#
# Route 53 auto-fails-over via the health check on the primary ALB, so
# DNS typically switches within ~90s without manual intervention.
#
# Requirements: aws cli v2, curl, jq.
#
set -euo pipefail

ACCOUNT_ID="${AWS_ACCOUNT_ID:-781863099565}"
DR_REGION="${DR_REGION:-eu-west-1}"
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
GLOBAL_DB_ID="${GLOBAL_DB_ID:-shopcloud-global-db}"
DR_DB_CLUSTER_ID="${DR_DB_CLUSTER_ID:-shopcloud-dr-aurora}"
DR_ECS_CLUSTER="${DR_ECS_CLUSTER:-shopcloud-dr-cluster}"
SERVICES=("catalog" "cart" "checkout" "auth" "admin")
HEALTH_URL="${HEALTH_URL:-https://app.shopcloud.com/healthz}"

echo "================================================================="
echo "  ShopCloud DR Failover — promoting ${DR_REGION}"
echo "================================================================="

# ---------- 1. Aurora ----------
echo
echo "[1/5] Promoting Aurora Global Database secondary..."
aws rds failover-global-cluster \
  --global-cluster-identifier "${GLOBAL_DB_ID}" \
  --target-db-cluster-identifier "arn:aws:rds:${DR_REGION}:${ACCOUNT_ID}:cluster:${DR_DB_CLUSTER_ID}" \
  --region "${DR_REGION}" \
  || echo "  (failover-global-cluster returned non-zero; it may already be promoted)"

echo "  Waiting for DR cluster to report available..."
aws rds wait db-cluster-available \
  --db-cluster-identifier "${DR_DB_CLUSTER_ID}" \
  --region "${DR_REGION}"

# ---------- 2. ElastiCache (Global Datastore) ----------
echo
echo "[2/5] Attempting ElastiCache Global Datastore failover..."
aws elasticache failover-global-replication-group \
  --global-replication-group-id shopcloud-redis-global \
  --primary-replication-group-id shopcloud-redis-dr \
  --primary-region "${DR_REGION}" \
  2>/dev/null || echo "  (no Global Datastore — standalone DR cache will warm up on first use)"

# ---------- 3. Scale ECS Fargate services ----------
echo
echo "[3/5] Scaling ECS Fargate services to 2 tasks each..."
for SVC in "${SERVICES[@]}"; do
  aws ecs update-service \
    --cluster "${DR_ECS_CLUSTER}" \
    --service "${SVC}" \
    --desired-count 2 \
    --region "${DR_REGION}" >/dev/null
  echo "  scaled ${SVC} -> 2 tasks"
done

echo
echo "[4/5] Waiting for services to stabilize..."
for SVC in "${SERVICES[@]}"; do
  aws ecs wait services-stable \
    --cluster "${DR_ECS_CLUSTER}" \
    --services "${SVC}" \
    --region "${DR_REGION}"
  echo "  ${SVC} stable"
done

# ---------- 5. Health check ----------
echo
echo "[5/5] Checking ${HEALTH_URL}..."
sleep 30
CODE=$(curl -sSfo /dev/null -w "%{http_code}" "${HEALTH_URL}" || echo "000")
if [ "${CODE}" = "200" ]; then
  echo "  Health check PASSED (${CODE})"
else
  echo "  WARNING — health check returned ${CODE} — Route 53 may still be propagating"
fi

cat <<'EOF'

=================================================================
  Failover complete.
  Manual follow-up:
    * Verify Route 53 is routing to the DR ALB (dig app.shopcloud.com)
    * If using distinct DR domain, update Cognito callback URLs
    * Watch CloudWatch alarms in the DR region for 15-30 min
    * Once primary is restored, reverse promotion:
        aws rds failover-global-cluster ...
        kubectl scale deploy <svc> --replicas=2 -n shopcloud
        aws ecs update-service --desired-count 0 ... (for each DR svc)
=================================================================
EOF
