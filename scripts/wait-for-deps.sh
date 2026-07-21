#!/usr/bin/env bash
#
# wait-for-deps.sh — Block Service A startup until service-b health responds.
# Does not wait on service-c (traffic contract: service-a must not call service-c).
# Docker Compose uses scripts/wait-for-deps.mjs instead.
#
set -Eeuo pipefail

DEPS=(
  "${SERVICE_B_HEALTH_URL:-http://service-b:3002/health}"
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
