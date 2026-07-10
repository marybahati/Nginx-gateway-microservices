#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
NORMAL_REQUESTS="${NORMAL_REQUESTS:-500}"
NORMAL_CONCURRENCY="${NORMAL_CONCURRENCY:-10}"
STRESS_REQUESTS="${STRESS_REQUESTS:-2000}"
STRESS_CONCURRENCY="${STRESS_CONCURRENCY:-50}"
FAILURE_REQUESTS="${FAILURE_REQUESTS:-300}"
FAILURE_CONCURRENCY="${FAILURE_CONCURRENCY:-10}"

log_event() {
  local event="$1"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"info\",\"service\":\"load-test\",\"event\":\"${event}\"}"
}

run_scenario() {
  local name="$1"
  local path="$2"
  local requests="$3"
  local concurrency="$4"

  log_event "load_test_started"
  echo "=== ${name} ==="
  echo "URL: ${BASE_URL}${path}"
  echo "Requests: ${requests}, Concurrency: ${concurrency}"
  echo ""

  local start end elapsed
  start=$(date +%s)
  seq 1 "${requests}" | xargs -P "${concurrency}" -I{} curl -fsS -o /dev/null -w "%{http_code}\n" \
    "${BASE_URL}${path}" -H "X-Request-ID: load-${name}-{}-$(date +%s)" || true
  end=$(date +%s)
  elapsed=$((end - start))

  echo ""
  echo "Completed in ${elapsed}s"
  log_event "load_test_completed"
  echo ""
}

echo "MELT load test"
echo "=============="
echo "Open Grafana (http://localhost:3030) and Jaeger (http://localhost:16686) before running."
echo ""

run_scenario "normal" "/service-a/greet-service-b" "${NORMAL_REQUESTS}" "${NORMAL_CONCURRENCY}"
run_scenario "stress" "/service-a/greet-service-b" "${STRESS_REQUESTS}" "${STRESS_CONCURRENCY}"
run_scenario "failure" "/service-a/lab/fail" "${FAILURE_REQUESTS}" "${FAILURE_CONCURRENCY}"

echo "Done."
echo "Next checks:"
echo "  • Prometheus alerts: http://localhost:9090/alerts"
echo "  • Grafana dashboard: http://localhost:3030/d/melt-overview"
echo "  • Jaeger traces: http://localhost:16686"
echo "  • Loki logs in Grafana Explore: {service=\"service-c\"}"
