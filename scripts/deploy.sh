#!/usr/bin/env bash
set -euo pipefail

REQUESTED_IMAGE_TAG="${1:-}"

if [ -z "$REQUESTED_IMAGE_TAG" ]; then
  echo "Usage: ./scripts/deploy.sh sha-<short-commit-hash>"
  echo "Example: ./scripts/deploy.sh sha-a1b2c3d"
  exit 1
fi

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ "$REQUESTED_IMAGE_TAG" != sha-* ]]; then
  echo "IMAGE_TAG must be commit-pinned and start with 'sha-'"
  echo "Example: ./scripts/deploy.sh sha-a1b2c3d"
  exit 1
fi

export IMAGE_TAG="$REQUESTED_IMAGE_TAG"
export APP_NAME="${APP_NAME:-devops100}"

if [ -z "${DOCKERHUB_USERNAME:-}" ]; then
  echo "Missing DOCKERHUB_USERNAME"
  echo "Set it with: export DOCKERHUB_USERNAME=<dockerhub-username>"
  exit 1
fi

echo "Deploying ${APP_NAME} using image tag: ${IMAGE_TAG}"
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d --remove-orphans
docker compose -f docker-compose.prod.yml ps
