#!/usr/bin/env bash
# Controlled failure drill for production-readiness evidence (incident-timeline.md).
# Injects Service B latency via Service A /lab/slow while generating greet traffic.
# Region: eu-west-1. Requires AWS credentials for the lab account.
set -euo pipefail

REGION="${AWS_REGION:-eu-west-1}"
DURATION_SEC="${DURATION_SEC:-420}"
CONCURRENCY="${CONCURRENCY:-8}"
INTERVAL_SEC="${INTERVAL_SEC:-2}"

if [[ "$REGION" != "eu-west-1" ]]; then
  echo "Group 5 must use eu-west-1" >&2
  exit 1
fi

echo "==> Caller"
aws sts get-caller-identity --region "$REGION"

ALB="${ALB_DNS:-}"
if [[ -z "$ALB" ]]; then
  ALB=$(aws elbv2 describe-load-balancers --names devops-g5-iac-alb --region "$REGION" \
    --query 'LoadBalancers[0].DNSName' --output text)
fi
BASE="http://${ALB}"
echo "ALB base: $BASE"

T0=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "T0 failure introduced: $T0"
echo "Record this in production-readiness/incident-timeline.md"

# Background: mixed greet + slow traffic to elevate p95 / TargetResponseTime
LOAD_PID=""
(
  end=$((SECONDS + DURATION_SEC))
  i=0
  while (( SECONDS < end )); do
    for _ in $(seq 1 "$CONCURRENCY"); do
      if (( i % 3 == 0 )); then
        curl -sS -o /dev/null -m 35 "${BASE}/lab/slow" &
      else
        curl -sS -o /dev/null -m 35 "${BASE}/greet-service-b" &
      fi
      i=$((i + 1))
    done
    wait || true
    sleep "$INTERVAL_SEC"
  done
) &
LOAD_PID=$!
echo "Load generator PID=$LOAD_PID (duration ${DURATION_SEC}s)"

echo "Watch alarms (Ctrl+C stops watcher only; load continues until duration ends):"
watch_end=$((SECONDS + DURATION_SEC + 60))
FIRST_ALARM=""
while (( SECONDS < watch_end )); do
  STATE=$(aws cloudwatch describe-alarms --region "$REGION" \
    --alarm-names devops-g5-iac-alb-latency-p95 \
    --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo "UNKNOWN")
  NOW=$(date -u +"%H:%M:%S")
  echo "[$NOW] devops-g5-iac-alb-latency-p95=$STATE"
  if [[ "$STATE" == "ALARM" && -z "$FIRST_ALARM" ]]; then
    FIRST_ALARM=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    echo "*** First ALARM at $FIRST_ALARM — note as Alert in incident-timeline.md"
  fi
  sleep 30
done

wait "$LOAD_PID" 2>/dev/null || true
T_MITIGATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "Mitigation (load stopped): $T_MITIGATE"

echo "==> Validate user journey (5 greets)"
ok=0
for i in 1 2 3 4 5; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" -m 35 "${BASE}/greet-service-b" || echo "000")
  echo "greet $i → $code"
  [[ "$code" == "200" ]] && ok=$((ok + 1))
  sleep 2
done

T_RESTORE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
echo "SLI check finished: $T_RESTORE (ok=$ok/5)"
echo
echo "Fill production-readiness/incident-timeline.md with:"
echo "  T0=$T0"
echo "  Alert=$FIRST_ALARM"
echo "  Mitigate=$T_MITIGATE"
echo "  SLI restored=$T_RESTORE"
echo "Capture: CloudWatch dashboard devops-g5-iac-reliability + alarm history"
echo "  aws cloudwatch describe-alarm-history --alarm-name devops-g5-iac-alb-latency-p95 --region $REGION"
