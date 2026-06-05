#!/usr/bin/env bash
# Print the live public app URL for the OCI container instance (OCI CLI, not Terraform state).
#
# Usage:
#   ./scripts/oci-app-url.sh
#   APP=$(./scripts/oci-app-url.sh) && curl -s "$APP/api/admin/session"

set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
PORT="${APP_PORT:-3000}"

INSTANCE_OCID="${CLOUD_STORE_OCID:-}"
if [[ -z "$INSTANCE_OCID" ]]; then
  INSTANCE_OCID="$(cd "$TF_DIR" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
fi
if [[ -z "$INSTANCE_OCID" ]]; then
  echo "error: set CLOUD_STORE_OCID or run from a terraform dir with container_instance_ocid output" >&2
  exit 1
fi

resolve_vnic_id() {
  oci container-instances container-instance get \
    --container-instance-id "$1" \
    --query 'data.vnics[0]."vnic-id"' \
    --raw-output 2>/dev/null || true
}

VNIC_ID="$(resolve_vnic_id "$INSTANCE_OCID")"
if [[ -z "$VNIC_ID" && -n "${CLOUD_STORE_OCID:-}" ]]; then
  TF_OCID="$(cd "$TF_DIR" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
  if [[ -n "$TF_OCID" && "$TF_OCID" != "$INSTANCE_OCID" ]]; then
    echo "warning: CLOUD_STORE_OCID is stale; using terraform output container_instance_ocid" >&2
    INSTANCE_OCID="$TF_OCID"
    VNIC_ID="$(resolve_vnic_id "$INSTANCE_OCID")"
  fi
fi
if [[ -z "$VNIC_ID" ]]; then
  echo "error: could not resolve VNIC for container instance $INSTANCE_OCID" >&2
  echo "hint: unset CLOUD_STORE_OCID or update it: export CLOUD_STORE_OCID=\$(cd terraform && terraform output -raw container_instance_ocid)" >&2
  exit 1
fi

PUBLIC_IP=$(oci network vnic get \
  --vnic-id "$VNIC_ID" \
  --query 'data."public-ip"' \
  --raw-output)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "null" ]]; then
  echo "error: no public IP on instance (still starting?)" >&2
  exit 1
fi

echo "http://${PUBLIC_IP}:${PORT}"
