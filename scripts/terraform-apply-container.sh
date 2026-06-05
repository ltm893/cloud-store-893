#!/usr/bin/env bash
# Run terraform apply in ./terraform with an IP-change warning when the container instance will change.
#
# Usage:
#   ./scripts/terraform-apply-container.sh           # plan + prompt if IP risk
#   ./scripts/terraform-apply-container.sh --yes     # apply without prompt
#   ./scripts/terraform-apply-container.sh plan-only # plan + warn only, no apply
#
# App code deploys should use: docker push + ./scripts/restart-container-instance.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
MODE="apply"
YES=""

for arg in "$@"; do
  case "$arg" in
    --yes) YES="--yes" ;;
    plan-only) MODE="plan-only" ;;
  esac
done

# shellcheck source=lib/oci-ip-warn.sh
source "$PROJECT_ROOT/scripts/lib/oci-ip-warn.sh"

if [[ ! -d "$TF_DIR" ]]; then
  echo "error: $TF_DIR not found" >&2
  exit 1
fi

set +e
oci_ip_terraform_plan_container_change "$TF_DIR"
plan_signal=$?
set -e

if [[ "$plan_signal" -eq 2 ]]; then
  exit 1
fi

if [[ "$MODE" == "plan-only" ]]; then
  exit 0
fi

if [[ "$plan_signal" -eq 1 ]]; then
  oci_ip_confirm_apply_or_exit "$YES"
fi

cd "$TF_DIR"
terraform apply

echo ""
echo "Post-apply:"
echo "  ./scripts/oci-app-url.sh"
echo "  cloud-store-refresh-ocid   # if defined in your shell profile"
