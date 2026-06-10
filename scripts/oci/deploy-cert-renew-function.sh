#!/usr/bin/env bash
# Build (linux/amd64), push, and update the cert-renew OCI Function image.
#
# OCI requires the image in OCIR *before* CreateFunction — on first deploy:
#   ./scripts/oci/deploy-cert-renew-function.sh --bootstrap
#   cd terraform && terraform apply
#
# After the function exists:
#   ./scripts/oci/deploy-cert-renew-function.sh
#
# Usage:
#   ./scripts/oci/deploy-cert-renew-function.sh --bootstrap   # build + push only (before first apply)
#   ./scripts/oci/deploy-cert-renew-function.sh               # build + push + oci fn update
#   ./scripts/oci/deploy-cert-renew-function.sh --apply       # push then terraform apply

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
RUN_APPLY=false
BOOTSTRAP=false

for arg in "$@"; do
  case "$arg" in
    --bootstrap) BOOTSTRAP=true ;;
    --apply) RUN_APPLY=true ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

resolve_image() {
  local img
  img="$(cd "$TF_DIR" && terraform output -raw cert_renew_function_image 2>/dev/null || true)"
  if [[ -n "$img" && "$img" != "null" ]]; then
    echo "$img"
    return
  fi
  img="$(cd "$TF_DIR" && terraform console -no-color <<< 'local.cert_renew_image' 2>/dev/null | tr -d '"' | tr -d '[:space:]')"
  if [[ -n "$img" ]]; then
    echo "$img"
    return
  fi
  echo "error: could not resolve cert-renew image (run from repo with terraform initialized)" >&2
  exit 1
}

IMAGE="$(resolve_image)"
FN_OCID="$(cd "$TF_DIR" && terraform output -raw cert_renew_function_ocid 2>/dev/null || true)"

echo "==> IMAGE=$IMAGE"
docker buildx build \
  --platform linux/amd64 \
  -t "$IMAGE" \
  "$PROJECT_ROOT/functions/cert-renew"

echo ""
echo "==> Pushing $IMAGE"
docker push "$IMAGE"

if [[ "$BOOTSTRAP" == true ]]; then
  echo ""
  echo "✅ Image pushed. Next:"
  echo "  cd terraform && terraform apply"
  exit 0
fi

if [[ "$RUN_APPLY" == true ]]; then
  echo ""
  echo "==> terraform apply"
  (cd "$TF_DIR" && terraform apply)
elif [[ -n "$FN_OCID" && "$FN_OCID" != "null" ]]; then
  echo ""
  echo "==> Updating function image (oci fn function update)"
  oci fn function update \
    --function-id "$FN_OCID" \
    --image "$IMAGE" \
    --force
else
  echo ""
  echo "warn: cert_renew_function_ocid missing — run: cd terraform && terraform apply"
fi

echo ""
echo "Next:"
echo "  ./scripts/oci/seed-certbot-state.sh"
echo "  ./scripts/oci/invoke-cert-renew-function.sh --dry-run"
