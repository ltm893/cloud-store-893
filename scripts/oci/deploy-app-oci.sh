#!/usr/bin/env bash
# Build, push, and deploy app code to OCI with a unique image tag (reliable image update).
#
# Restart alone may not run new code if the instance cached an old :latest digest.
# This script pushes a dated tag and runs terraform apply with ocir_image_tag set.
#
# Usage:
#   ./scripts/oci/deploy-app-oci.sh
#   ./scripts/oci/deploy-app-oci.sh 20260605b
#   ./scripts/oci/deploy-app-oci.sh --recover-network   # auto-run reattach after replace
#
# After apply, reattach reserved public IP if oci.cloudstore893.com stops responding.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
OCI_SCRIPTS="$PROJECT_ROOT/scripts/oci"

# shellcheck source=lib/oci-ip-warn.sh
source "$OCI_SCRIPTS/lib/oci-ip-warn.sh"
TAG=""
RECOVER_NETWORK=""

for arg in "$@"; do
  case "$arg" in
    --recover-network) RECOVER_NETWORK="--recover-network" ;;
    *)
      if [[ -z "$TAG" ]]; then
        TAG="$arg"
      fi
      ;;
  esac
done

TAG="${TAG:-$(date +%Y%m%d%H%M%S)}"
BUILD_ID="${TAG}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found" >&2
  exit 1
fi

IMAGE_BASE="$(cd "$TF_DIR" && terraform output -raw ocir_image_path)"
IMAGE_BASE="${IMAGE_BASE%:*}"
IMAGE_TAGGED="${IMAGE_BASE}:${TAG}"
IMAGE_LATEST="${IMAGE_BASE}:latest"

echo "==> BUILD_ID=$BUILD_ID"
echo "==> IMAGE_TAGGED=$IMAGE_TAGGED"

docker buildx build \
  --platform linux/arm64 \
  --build-arg BUILD_ID="$BUILD_ID" \
  -t "$IMAGE_TAGGED" \
  -t "$IMAGE_LATEST" \
  "$PROJECT_ROOT"

docker push "$IMAGE_TAGGED"
docker push "$IMAGE_LATEST"

echo ""
set +e
oci_ip_terraform_plan_container_change "$TF_DIR"
plan_signal=$?
set -e
if [[ "$plan_signal" -eq 2 ]]; then
  echo "error: terraform plan failed" >&2
  exit 1
fi

echo "==> terraform apply -var ocir_image_tag=${TAG}"
cd "$TF_DIR"
terraform apply -var="ocir_image_tag=${TAG}" -var="idp_signin_debug=true" -auto-approve

echo ""
echo "==> Verify build on running app:"
echo "    APP=\$(./scripts/oci/confirm-public-url.sh) && curl -s \"\${APP}api/build-info\""
echo ""

if [[ "$plan_signal" -eq 1 ]]; then
  oci_ip_offer_recover_network "$RECOVER_NETWORK" "$OCI_SCRIPTS"
else
  echo "Reserved IP should still be attached (instance not replaced)."
fi

echo ""
echo "Optional debug OAuth errors on screen:"
echo "    add IDP_SIGNIN_DEBUG=true to .env, sync-container-env-to-terraform.sh, terraform apply"
