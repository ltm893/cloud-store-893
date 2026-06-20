#!/usr/bin/env bash
# Build, push, and restart OCI app code without replacing the container instance.
#
# Preferred path after changing server.js, lib/, or public/. Keeps the public IP
# (including a reserved IP) attached — unlike terraform apply on the container.
#
# Usage:
#   ./scripts/oci/redeploy-app-code.sh "short deploy description"
#   ./scripts/oci/redeploy-app-code.sh "short deploy description" --no-wait
#
# BUILD_ID is always YYYYMMDDHHmmss. BUILD_LABEL is the required description shown in
# GET /api/build-info and the Systems tab.
#
# For env var changes (replaces instance — may detach reserved IP):
#   ./scripts/oci/sync-container-env-to-terraform.sh
#   ./scripts/oci/terraform-apply-container.sh
#
# For a new image tag + terraform apply (also may replace instance):
#   ./scripts/oci/deploy-app-oci.sh <tag>

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
OCI_SCRIPTS="$PROJECT_ROOT/scripts/oci"

BUILD_LABEL=""
RESTART_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-wait) RESTART_ARGS+=(--no-wait) ;;
    --help|-h)
      sed -n '2,22p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [[ -z "$BUILD_LABEL" ]]; then
        BUILD_LABEL="$arg"
      else
        echo "error: unexpected argument: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "${BUILD_LABEL//[[:space:]]/}" ]]; then
  echo "error: BUILD_LABEL required" >&2
  echo "usage: $0 \"deploy description\" [--no-wait]" >&2
  exit 1
fi

BUILD_ID="$(date +%Y%m%d%H%M%S)"
GIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found" >&2
  exit 1
fi

IMAGE="$(cd "$TF_DIR" && terraform output -raw ocir_image_path)"

echo "==> BUILD_ID=$BUILD_ID"
echo "==> BUILD_LABEL=$BUILD_LABEL"
echo "==> GIT_SHA=${GIT_SHA:-unknown}"
echo "==> IMAGE=$IMAGE"
echo ""

if command -v oci >/dev/null 2>&1; then
  echo "==> Refreshing Systems OCI manifest"
  "$OCI_SCRIPTS/sync-systems-manifest.sh" || echo "warn: sync-systems-manifest.sh failed (continuing)" >&2
  echo ""
fi

docker buildx build \
  --platform linux/arm64 \
  --build-arg BUILD_ID="$BUILD_ID" \
  --build-arg BUILD_LABEL="$BUILD_LABEL" \
  --build-arg GIT_SHA="${GIT_SHA:-unknown}" \
  -t "$IMAGE" \
  "$PROJECT_ROOT"

echo ""
echo "==> Pushing $IMAGE"
docker push "$IMAGE"

echo ""
echo "==> Restarting container instance"
# bash 3.2 + set -u treats empty "${RESTART_ARGS[@]}" as unbound on macOS
if ((${#RESTART_ARGS[@]} > 0)); then
  "$OCI_SCRIPTS/restart-container-instance.sh" "${RESTART_ARGS[@]}"
else
  "$OCI_SCRIPTS/restart-container-instance.sh"
fi

echo ""
if ((${#RESTART_ARGS[@]} > 0)); then
  echo "==> Verify build (skipped — restart used --no-wait):"
  echo "    $OCI_SCRIPTS/wait-for-app-health.sh --expected-build-id $BUILD_ID"
else
  echo "==> Waiting for app health (502 right after restart is normal until Node is up):"
  if ! "$OCI_SCRIPTS/wait-for-app-health.sh" --expected-build-id "$BUILD_ID"; then
    exit 1
  fi
fi
