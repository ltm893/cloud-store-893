#!/usr/bin/env bash
# Build, push, and restart OCI app code without replacing the container instance.
#
# Preferred path after changing server.js, lib/, or public/. Keeps the public IP
# (including a reserved IP) attached — unlike terraform apply on the container.
#
# Usage:
#   ./scripts/oci/redeploy-app-code.sh
#   ./scripts/oci/redeploy-app-code.sh my-feature-20260606
#   ./scripts/oci/redeploy-app-code.sh --no-wait
#   ./scripts/oci/redeploy-app-code.sh my-feature-20260606 --no-wait
#
# BUILD_ID defaults to a timestamp; it is exposed at GET /api/build-info for verification.
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

BUILD_ID=""
RESTART_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-wait) RESTART_ARGS+=(--no-wait) ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [[ -z "$BUILD_ID" ]]; then
        BUILD_ID="$arg"
      else
        echo "error: unexpected argument: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

BUILD_ID="${BUILD_ID:-$(date +%Y%m%d%H%M%S)}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found" >&2
  exit 1
fi

IMAGE="$(cd "$TF_DIR" && terraform output -raw ocir_image_path)"

echo "==> BUILD_ID=$BUILD_ID"
echo "==> IMAGE=$IMAGE"
echo ""

docker buildx build \
  --platform linux/arm64 \
  --build-arg BUILD_ID="$BUILD_ID" \
  -t "$IMAGE" \
  "$PROJECT_ROOT"

echo ""
echo "==> Pushing $IMAGE"
docker push "$IMAGE"

echo ""
echo "==> Restarting container instance"
"$OCI_SCRIPTS/restart-container-instance.sh" "${RESTART_ARGS[@]}"

echo ""
echo "==> Verify build on running app:"
APP="$("$OCI_SCRIPTS/oci-app-url.sh" 2>/dev/null || true)"
if [[ -n "$APP" ]]; then
  curl -sS "${APP}/api/build-info" || true
  echo ""
else
  echo "    APP=\$($OCI_SCRIPTS/oci-app-url.sh)"
  echo "    curl -s \"\$APP/api/build-info\""
fi
