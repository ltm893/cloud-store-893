#!/usr/bin/env bash
# Resolve and print the live public app URL (OCI LB hostname, tunnel, or container IP).
#
# Usage:
#   ./scripts/oci/confirm-public-url.sh
#   APP=$(./scripts/oci/confirm-public-url.sh) && curl -s "$APP/api/admin/session"
#
# With probe (prints URL on stdout; health check on stderr):
#   ./scripts/oci/confirm-public-url.sh --probe

set -euo pipefail

PROBE=0
for arg in "$@"; do
  case "$arg" in
    --probe) PROBE=1 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform" && pwd)"
PORT="${APP_PORT:-3000}"

resolve_url() {
  if [[ -d "$TF_DIR" ]] && command -v terraform >/dev/null 2>&1; then
    local https_url
    https_url="$(cd "$TF_DIR" && terraform output -raw app_url_https 2>/dev/null || true)"
    if [[ -n "$https_url" && "$https_url" != "null" ]]; then
      printf '%s' "$https_url"
      return 0
    fi
  fi

  local hostname="${APP_PUBLIC_HOSTNAME:-${CLOUDFLARE_TUNNEL_HOSTNAME:-}}"
  if [[ -n "$hostname" ]]; then
    printf 'https://%s/' "$hostname"
    return 0
  fi

  local instance_ocid="${CLOUD_STORE_OCID:-}"
  if [[ -z "$instance_ocid" ]]; then
    instance_ocid="$(cd "$TF_DIR" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
  fi
  if [[ -z "$instance_ocid" ]]; then
    echo "error: set CLOUD_STORE_OCID or run from a terraform dir with container_instance_ocid output" >&2
    return 1
  fi

  resolve_vnic_id() {
    oci container-instances container-instance get \
      --container-instance-id "$1" \
      --query 'data.vnics[0]."vnic-id"' \
      --raw-output 2>/dev/null || true
  }

  local vnic_id
  vnic_id="$(resolve_vnic_id "$instance_ocid")"
  if [[ -z "$vnic_id" && -n "${CLOUD_STORE_OCID:-}" ]]; then
    local tf_ocid
    tf_ocid="$(cd "$TF_DIR" && terraform output -raw container_instance_ocid 2>/dev/null || true)"
    if [[ -n "$tf_ocid" && "$tf_ocid" != "$instance_ocid" ]]; then
      echo "warning: CLOUD_STORE_OCID is stale; using terraform output container_instance_ocid" >&2
      instance_ocid="$tf_ocid"
      vnic_id="$(resolve_vnic_id "$instance_ocid")"
    fi
  fi
  if [[ -z "$vnic_id" ]]; then
    echo "error: could not resolve VNIC for container instance $instance_ocid" >&2
    echo "hint: unset CLOUD_STORE_OCID or update it: export CLOUD_STORE_OCID=\$(cd terraform && terraform output -raw container_instance_ocid)" >&2
    return 1
  fi

  local public_ip
  public_ip=$(oci network vnic get \
    --vnic-id "$vnic_id" \
    --query 'data."public-ip"' \
    --raw-output)

  if [[ -z "$public_ip" || "$public_ip" == "null" ]]; then
    echo "error: no public IP on instance (still starting?)" >&2
    return 1
  fi

  printf 'http://%s:%s/' "$public_ip" "$PORT"
}

APP_URL="$(resolve_url)"
printf '%s\n' "$APP_URL"

if [[ "$PROBE" -eq 1 ]]; then
  if curl -sk --max-time 8 -o /dev/null -w "%{http_code}" "${APP_URL}api/build-info" | grep -q '^200$'; then
    echo "ok: GET ${APP_URL}api/build-info → 200" >&2
  else
    echo "warn: GET ${APP_URL}api/build-info did not return 200" >&2
    exit 1
  fi
fi
