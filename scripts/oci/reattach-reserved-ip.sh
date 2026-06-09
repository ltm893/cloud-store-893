#!/usr/bin/env bash
# Reattach the reserved public IP to the current container instance VNIC after replace.
#
# Usage:
#   ./scripts/oci/reattach-reserved-ip.sh
#   ./scripts/oci/reattach-reserved-ip.sh --yes
#   ./scripts/oci/reattach-reserved-ip.sh --dry-run
#   ./scripts/oci/reattach-reserved-ip.sh --refresh-ocid   # print/export CLOUD_STORE_OCID
#   ./scripts/oci/reattach-reserved-ip.sh --update-idp     # call idp-update-redirect-uris.sh after reattach
#
# Env:
#   CLOUD_STORE_RESERVED_PUBLIC_IP_OCID  (defaults to project reserved IP OCID)
#   CLOUD_STORE_OCID                     (refreshed from terraform unless set for display only)
#   APP_PORT                             (default 3000)
#   APP_PUBLIC_HOST                      (default oci.cloudstore893.com — used for curl verify)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/terraform"
OCI_SCRIPTS="$PROJECT_ROOT/scripts/oci"

DEFAULT_RESERVED_OCID="ocid1.publicip.oc1.iad.amaaaaaa36usv6qatlrxmwbk2ehpwj5wr43rusqjcobno54msiok4mqfbh7q"
PORT="${APP_PORT:-3000}"
APP_HOST="${APP_PUBLIC_HOST:-oci.cloudstore893.com}"

DRY_RUN=false
AUTO_YES=false
REFRESH_OCID=false
UPDATE_IDP=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) AUTO_YES=true ;;
    --refresh-ocid) REFRESH_OCID=true ;;
    --update-idp) UPDATE_IDP=true ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

if [[ "${AUTO_YES:-}" == "1" ]]; then
  AUTO_YES=true
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

RESERVED_OCID="${CLOUD_STORE_RESERVED_PUBLIC_IP_OCID:-$DEFAULT_RESERVED_OCID}"

echo "==> Reattach reserved public IP to container instance"
echo "    reserved public IP OCID: $RESERVED_OCID"
echo ""

# Step 1: current container instance from terraform (always fresh)
INSTANCE_OCID="$(cd "$TF_DIR" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
if [[ -z "$INSTANCE_OCID" ]]; then
  echo "error: could not read terraform output container_instance_ocid" >&2
  exit 1
fi

echo "    container instance OCID: $INSTANCE_OCID"

if [[ "$REFRESH_OCID" == "true" ]]; then
  export CLOUD_STORE_OCID="$INSTANCE_OCID"
  echo ""
  echo "export CLOUD_STORE_OCID=$INSTANCE_OCID"
  echo ""
fi

# Step 2: VNIC and primary private IP
VNIC_ID="$(oci container-instances container-instance get \
  --container-instance-id "$INSTANCE_OCID" \
  --query 'data.vnics[0]."vnic-id"' \
  --raw-output)"

if [[ -z "$VNIC_ID" || "$VNIC_ID" == "null" ]]; then
  echo "error: could not resolve VNIC for container instance $INSTANCE_OCID" >&2
  exit 1
fi

PRIVATE_IP_ID="$(oci network private-ip list \
  --vnic-id "$VNIC_ID" \
  --query 'data[0].id' \
  --raw-output)"

if [[ -z "$PRIVATE_IP_ID" || "$PRIVATE_IP_ID" == "null" ]]; then
  echo "error: could not resolve primary private IP for VNIC $VNIC_ID" >&2
  exit 1
fi

echo "    VNIC ID:        $VNIC_ID"
echo "    private IP ID:  $PRIVATE_IP_ID"
echo ""

RESERVED_STATE="$(oci network public-ip get \
  --public-ip-id "$RESERVED_OCID" \
  --query 'data."lifecycle-state"' \
  --raw-output 2>/dev/null || true)"
RESERVED_ASSIGNED_PRIVATE="$(oci network public-ip get \
  --public-ip-id "$RESERVED_OCID" \
  --query 'data."private-ip-id"' \
  --raw-output 2>/dev/null || true)"
RESERVED_IP="$(oci network public-ip get \
  --public-ip-id "$RESERVED_OCID" \
  --query 'data."ip-address"' \
  --raw-output 2>/dev/null || true)"

echo "── Reserved public IP (before) ──"
oci network public-ip get \
  --public-ip-id "$RESERVED_OCID" \
  --query 'data.{"ip":"ip-address","state":"lifecycle-state","assigned":"private-ip-id"}' \
  --output table 2>/dev/null || true
echo ""

NEEDS_REATTACH=true
if [[ "$RESERVED_STATE" == "ASSIGNED" && "$RESERVED_ASSIGNED_PRIVATE" == "$PRIVATE_IP_ID" ]]; then
  NEEDS_REATTACH=false
  echo "Reserved IP is already assigned to this instance's primary private IP — skipping update."
  echo ""
fi

detach_ephemeral_public_ips() {
  local vnic_public compartment ad ephemeral_id
  vnic_public="$(oci network vnic get \
    --vnic-id "$VNIC_ID" \
    --query 'data."public-ip"' \
    --raw-output 2>/dev/null || true)"
  if [[ -z "$vnic_public" || "$vnic_public" == "null" ]]; then
    return 0
  fi
  if [[ -n "${RESERVED_IP:-}" && "$vnic_public" == "$RESERVED_IP" ]]; then
    return 0
  fi

  compartment="$(oci container-instances container-instance get \
    --container-instance-id "$INSTANCE_OCID" \
    --query 'data."compartment-id"' \
    --raw-output)"
  ad="$(oci network private-ip get \
    --private-ip-id "$PRIVATE_IP_ID" \
    --query 'data."availability-domain"' \
    --raw-output)"

  ephemeral_id="$(oci network public-ip list \
    --compartment-id "$compartment" \
    --lifetime EPHEMERAL \
    --scope AVAILABILITY_DOMAIN \
    --availability-domain "$ad" \
    --query "data[?\"ip-address\"=='${vnic_public}'].id | [0]" \
    --raw-output 2>/dev/null || true)"

  if [[ -n "$ephemeral_id" && "$ephemeral_id" != "null" && "$ephemeral_id" == ocid1.* ]]; then
    echo "==> Removing ephemeral public IP on new VNIC ($ephemeral_id / $vnic_public)..."
    oci network public-ip delete --public-ip-id "$ephemeral_id" --force --wait-for-state TERMINATED
  fi
}

if [[ "$NEEDS_REATTACH" == "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would run:"
    echo "  # delete any EPHEMERAL public IP on private IP $PRIVATE_IP_ID (if present)"
    echo "  oci network public-ip update \\"
    echo "    --public-ip-id \"$RESERVED_OCID\" \\"
    echo "    --private-ip-id \"$PRIVATE_IP_ID\" \\"
    echo "    --wait-for-state ASSIGNED"
    echo ""
  else
    if [[ "$AUTO_YES" != "true" && "${AUTO_YES:-}" != "1" ]]; then
      if [[ ! -t 0 ]]; then
        echo "error: reattach required; re-run with --yes or AUTO_YES=1" >&2
        exit 1
      fi
      read -r -p "Reattach reserved IP to the new VNIC? [y/N] " ans
      case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
      esac
    fi

    echo "==> Reattaching reserved public IP..."
    detach_ephemeral_public_ips
    oci network public-ip update \
      --public-ip-id "$RESERVED_OCID" \
      --private-ip-id "$PRIVATE_IP_ID" \
      --wait-for-state ASSIGNED

    echo ""
    echo "── Reserved public IP (after) ──"
    oci network public-ip get \
      --public-ip-id "$RESERVED_OCID" \
      --query 'data.{"ip":"ip-address","state":"lifecycle-state","assigned":"private-ip-id"}' \
      --output table
    echo ""
  fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] would verify:"
  echo "  curl -s -o /dev/null -w '%{http_code}' http://${APP_HOST}:${PORT}/"
  echo "  $OCI_SCRIPTS/confirm-public-url.sh"
  exit 0
fi

# Step 4: verify app
echo "==> Verify app"
APP_URL="http://${APP_HOST}:${PORT}"
http_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$APP_URL/" || true)"
echo "    curl ${APP_URL}/ → HTTP ${http_code:-failed}"

if [[ -n "${RESERVED_IP:-}" && "$RESERVED_IP" != "null" ]]; then
  reserved_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://${RESERVED_IP}:${PORT}/" || true)"
  echo "    curl http://${RESERVED_IP}:${PORT}/ → HTTP ${reserved_code:-failed}"
fi

echo ""
echo "    Live URL via OCI CLI:"
export CLOUD_STORE_OCID="$INSTANCE_OCID"
live_url="$("$OCI_SCRIPTS/confirm-public-url.sh" 2>/dev/null || true)"
if [[ -n "$live_url" ]]; then
  echo "      $live_url"
else
  echo "      (confirm-public-url.sh failed — check CLOUD_STORE_OCID and instance state)"
fi
echo ""

if [[ "$UPDATE_IDP" == "true" ]]; then
  if [[ -z "${IDP_DOMAIN_ENDPOINT:-}" || -z "${APP_PUBLIC_HOST:-}" ]]; then
    echo "warning: --update-idp skipped — set IDP_DOMAIN_ENDPOINT and APP_PUBLIC_HOST" >&2
  else
    echo "==> Updating IdCS redirect URIs"
    "$OCI_SCRIPTS/idp-update-redirect-uris.sh"
  fi
fi

if [[ "$REFRESH_OCID" != "true" ]]; then
  echo "Tip: refresh shell OCID — export CLOUD_STORE_OCID=$INSTANCE_OCID"
fi
