#!/usr/bin/env bash
# Resolve and print the live public app URL (OCI LB hostname, tunnel, or container IP).
#
# Usage:
#   ./scripts/oci/confirm-public-url.sh
#   CLOUD_STORE_ENV=dev ./scripts/oci/confirm-public-url.sh
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
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${APP_PORT:-3000}"

# shellcheck source=lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"

resolve_url() {
  if [[ -d "$TF_DIR" ]] && command -v terraform >/dev/null 2>&1; then
    local https_url
    https_url="$(cloud_store_tf_output app_url_https || true)"
    if [[ -n "$https_url" && "$https_url" != "null" ]]; then
      printf '%s' "$https_url"
      return 0
    fi
  fi

  local hostname="${APP_PUBLIC_HOSTNAME:-${CLOUDFLARE_TUNNEL_HOSTNAME:-$CLOUD_STORE_PUBLIC_HOSTNAME}}"
  if [[ -n "$hostname" ]]; then
    printf 'https://%s/' "$hostname"
    return 0
  fi

  local instance_ocid
  instance_ocid="$(cloud_store_container_ocid_from_env)"
  if [[ -z "$instance_ocid" ]]; then
    instance_ocid="$(cloud_store_tf_output container_instance_ocid || true)"
  fi
  if [[ -z "$instance_ocid" ]]; then
    echo "error: set $(cloud_store_container_ocid_var) or run from a terraform dir with container_instance_ocid output" >&2
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
  if [[ -z "$vnic_id" && -n "$(cloud_store_container_ocid_from_env)" ]]; then
    local tf_ocid env_ocid
    tf_ocid="$(cloud_store_tf_output container_instance_ocid || true)"
    env_ocid="$(cloud_store_container_ocid_from_env)"
    if [[ -n "$tf_ocid" && "$tf_ocid" != "$env_ocid" ]]; then
      echo "warning: $(cloud_store_container_ocid_var) is stale; using terraform output container_instance_ocid" >&2
      instance_ocid="$tf_ocid"
      vnic_id="$(resolve_vnic_id "$instance_ocid")"
    fi
  fi
  if [[ -z "$vnic_id" ]]; then
    echo "error: could not resolve VNIC for container instance $instance_ocid" >&2
    echo "hint: update $(cloud_store_container_ocid_var) from terraform output (see docs/oci-dev-environment.md)" >&2
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
# No trailing slash — safe for "${APP}/api/..." (avoids //api/... 404s).
APP_URL="${APP_URL%/}"
printf '%s\n' "$APP_URL"

if [[ "$PROBE" -eq 1 ]]; then
  if curl -sk --max-time 8 -o /dev/null -w "%{http_code}" "${APP_URL}/api/build-info" | grep -q '^200$'; then
    echo "ok: GET ${APP_URL}/api/build-info → 200" >&2
  else
    echo "warn: GET ${APP_URL}/api/build-info did not return 200" >&2
    exit 1
  fi
fi
