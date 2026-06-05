#!/usr/bin/env bash
# restart-container-instance.sh
#
# Restart the OCI container instance for this Terraform project.
#
# Usage:
#   ./scripts/oci/restart-container-instance.sh
#   ./scripts/oci/restart-container-instance.sh --no-wait
#
# Requirements:
# - oci CLI authenticated
# - terraform initialized in ./terraform

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
WAIT_FOR_ACTIVE=true

if [[ "${1:-}" == "--no-wait" ]]; then
  WAIT_FOR_ACTIVE=false
fi

if ! command -v oci >/dev/null 2>&1; then
  echo "error: oci CLI not found in PATH" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "error: terraform not found in PATH" >&2
  exit 1
fi

if [[ ! -d "$TF_DIR" ]]; then
  echo "error: terraform directory not found at $TF_DIR" >&2
  exit 1
fi

cd "$TF_DIR"

OCI_ID="$(terraform output -raw container_instance_ocid 2>/dev/null || true)"
if [[ -z "$OCI_ID" ]]; then
  echo "error: could not read terraform output 'container_instance_ocid'" >&2
  echo "hint: run this from a repo with initialized terraform state" >&2
  exit 1
fi

echo "Restarting OCI container instance:"
echo "  $OCI_ID"
echo ""
echo "Note: restart pulls the latest :latest image but does NOT replace the instance."
echo "      Public IP should stay the same (including a reserved IP if attached)."
echo "      Use ./scripts/oci/terraform-apply-container.sh only for env changes — that can change IP."
echo ""

if command -v oci >/dev/null 2>&1 && [[ -n "${CLOUD_STORE_RESERVED_PUBLIC_IP_OCID:-}" ]]; then
  reserved_state="$(oci network public-ip get \
    --public-ip-id "$CLOUD_STORE_RESERVED_PUBLIC_IP_OCID" \
    --query 'data."lifecycle-state"' \
    --raw-output 2>/dev/null || true)"
  if [[ "$reserved_state" == "AVAILABLE" ]]; then
    echo "WARNING: reserved public IP is AVAILABLE (not attached). App may only be reachable on the ephemeral IP."
    echo "         Run ./scripts/oci/oci-app-url.sh for the live URL."
    echo ""
  fi
fi
if [[ "$WAIT_FOR_ACTIVE" == "true" ]]; then
  oci container-instances container-instance restart \
    --container-instance-id "$OCI_ID" \
    --wait-for-state SUCCEEDED
  LIFECYCLE_STATE="$(oci container-instances container-instance get \
    --container-instance-id "$OCI_ID" \
    --query 'data."lifecycle-state"' \
    --raw-output)"
  echo "Restart request succeeded. lifecycle-state=$LIFECYCLE_STATE"
else
  oci container-instances container-instance restart \
    --container-instance-id "$OCI_ID"
  echo "Restart requested (not waiting for ACTIVE)."
fi

