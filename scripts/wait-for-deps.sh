#!/usr/bin/env bash
#
# wait-for-deps.sh — Block Service A startup until B and C health endpoints respond.
# Used as a pre-start gate in Docker Compose (service-a container command).
#
set -Eeuo pipefail

DEPS=(
  "${SERVICE_B_HEALTH_URL:-http://service-b:3002/health}"
  "${SERVICE_C_HEALTH_URL:-http://service-c:3003/health}"
)

MAX_ATTEMPTS="${WAIT_FOR_DEPS_ATTEMPTS:-30}"
SLEEP_SEC="${WAIT_FOR_DEPS_INTERVAL:-2}"

for url in "${DEPS[@]}"; do
  attempt=1
  while ! curl -sf --max-time 2 "$url" >/dev/null; do
    if (( attempt >= MAX_ATTEMPTS )); then
      printf 'Dependency not ready after %s attempts: %s\n' "$MAX_ATTEMPTS" "$url" >&2
      exit 1
    fi
    printf 'Waiting for %s (attempt %s/%s)...\n' "$url" "$attempt" "$MAX_ATTEMPTS" >&2
    sleep "$SLEEP_SEC"
    ((attempt++))
  done
  printf 'Ready: %s\n' "$url"
done
