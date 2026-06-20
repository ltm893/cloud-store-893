#!/usr/bin/env bash
# Build, push, and deploy OCI app code with a unique image tag.
#
# OCI container instances cache the image digest at create time — restart alone does
# not pull a new :latest. This script pushes BUILD_ID as the image tag and runs
# terraform apply so the instance runs the new code.
#
# Usage:
#   ./scripts/oci/redeploy-app-code.sh "short deploy description"
#   ./scripts/oci/redeploy-app-code.sh "short deploy description" --no-wait
#   AUTO_YES=1 ./scripts/oci/redeploy-app-code.sh "label"   # skip IP-change prompt
#
# BUILD_ID is always YYYYMMDDHHmmss. BUILD_LABEL is the required description shown in
# GET /api/build-info and the Systems tab.
#
# For env var changes (no image tag change):
#   ./scripts/oci/sync-container-env-to-terraform.sh
#   ./scripts/oci/terraform-apply-container.sh
#
# Legacy restart-only (does not update cached image):
#   ./scripts/oci/restart-container-instance.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"
TF_DIR="$CLOUD_STORE_TF_DIR"
OCI_SCRIPTS="$PROJECT_ROOT/scripts/oci"
# shellcheck source=lib/oci-ip-warn.sh
source "$OCI_SCRIPTS/lib/oci-ip-warn.sh"

BUILD_LABEL=""
RESTART_ARGS=()
APPLY_YES=""

for arg in "$@"; do
  case "$arg" in
    --no-wait) RESTART_ARGS+=(--no-wait) ;;
    --yes) APPLY_YES="--yes" ;;
    --help|-h)
      sed -n '2,24p' "$0" | sed 's/^# \?//'
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
  echo "usage: $0 \"deploy description\" [--no-wait] [--yes]" >&2
  exit 1
fi

BUILD_ID="$(date +%Y%m%d%H%M%S)"
GIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found" >&2
  exit 1
fi

IMAGE_LATEST="$(cloud_store_tf_output ocir_image_path)"
IMAGE_BASE="${IMAGE_LATEST%:*}"
IMAGE_TAGGED="${IMAGE_BASE}:${BUILD_ID}"

echo "==> BUILD_ID=$BUILD_ID"
echo "==> BUILD_LABEL=$BUILD_LABEL"
echo "==> GIT_SHA=${GIT_SHA:-unknown}"
echo "==> ENV=$(cloud_store_env_label)"
echo "==> IMAGE_TAGGED=$IMAGE_TAGGED"
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
  -t "$IMAGE_TAGGED" \
  -t "$IMAGE_LATEST" \
  "$PROJECT_ROOT"

echo ""
echo "==> Pushing $IMAGE_TAGGED and :latest"
docker push "$IMAGE_TAGGED"
docker push "$IMAGE_LATEST"

echo ""
set +e
oci_ip_terraform_plan_container_change "$TF_DIR" -var="ocir_image_tag=${BUILD_ID}"
plan_signal=$?
set -e
if [[ "$plan_signal" -eq 2 ]]; then
  echo "error: terraform plan failed" >&2
  exit 1
fi

if [[ "$plan_signal" -eq 1 ]]; then
  oci_ip_confirm_apply_or_exit "$APPLY_YES"
fi

echo "==> terraform apply -var ocir_image_tag=${BUILD_ID} ($(cloud_store_env_label))"
cd "$TF_DIR"
cloud_store_tf apply -var="ocir_image_tag=${BUILD_ID}" -auto-approve

if [[ "$plan_signal" -eq 1 ]]; then
  oci_ip_offer_recover_network "" "$OCI_SCRIPTS"
  echo ""
  echo "hint: export $(cloud_store_container_ocid_var)=\"\$(cloud_store_tf_output container_instance_ocid)\""
  if [[ "$CLOUD_STORE_ENV" == "dev" ]]; then
    echo ""
    echo "==> Syncing dev DNS A record (LB IP may differ after container replace)"
    "$OCI_SCRIPTS/dev-dns-a-record.sh" || echo "warn: dev-dns-a-record.sh failed — run manually" >&2
  fi
fi

echo ""
if ((${#RESTART_ARGS[@]} > 0)); then
  echo "==> Verify build (skipped — used --no-wait):"
  echo "    $OCI_SCRIPTS/wait-for-app-health.sh --expected-build-id $BUILD_ID"
else
  echo "==> Waiting for app health (502 right after apply is normal until Node is up):"
  if ! "$OCI_SCRIPTS/wait-for-app-health.sh" --expected-build-id "$BUILD_ID"; then
    exit 1
  fi
fi
