#!/usr/bin/env bash
# Run terraform apply in ./terraform with an IP-change warning when the container instance will change.
#
# Usage:
#   ./scripts/oci/terraform-apply-container.sh                  # plan + prompt if IP risk
#   ./scripts/oci/terraform-apply-container.sh --yes            # apply without prompt
#   ./scripts/oci/terraform-apply-container.sh plan-only        # plan + warn only, no apply
#   ./scripts/oci/terraform-apply-container.sh --recover-network  # offer/auto reattach after replace
#
# App code deploys should use: docker push + ./scripts/oci/restart-container-instance.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
OCI_SCRIPTS="$PROJECT_ROOT/scripts/oci"
MODE="apply"
YES=""
RECOVER_NETWORK=""

for arg in "$@"; do
  case "$arg" in
    --yes) YES="--yes" ;;
    --recover-network) RECOVER_NETWORK="--recover-network" ;;
    plan-only) MODE="plan-only" ;;
  esac
done

# shellcheck source=lib/oci-ip-warn.sh
source "$PROJECT_ROOT/scripts/oci/lib/oci-ip-warn.sh"

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
if [[ "$YES" == "--yes" ]]; then
  terraform apply -auto-approve
else
  terraform apply
fi

if [[ "$plan_signal" -eq 1 ]]; then
  oci_ip_offer_recover_network "$RECOVER_NETWORK" "$OCI_SCRIPTS"
else
  echo ""
  echo "Post-apply: instance unchanged — reserved IP should still be attached."
  echo "  ./scripts/oci/confirm-public-url.sh"
fi
