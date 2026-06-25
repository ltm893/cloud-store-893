#!/usr/bin/env bash
# Poll the public app until GET /api/build-info returns 200.
#
# Usage:
#   ./scripts/oci/wait-for-app-health.sh
#   ./scripts/oci/wait-for-app-health.sh --expected-build-id 20260619143022
#   ./scripts/oci/wait-for-app-health.sh --app-url https://oci.cloudstore893.com --timeout 240
#
# Prints the build-info JSON body on success (stdout). Progress on stderr.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/../../terraform" && pwd)"

# shellcheck source=lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"

APP_URL=""
EXPECTED_BUILD_ID=""
TIMEOUT_SEC=180
INTERVAL_SEC=10

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-url)
      APP_URL="${2%/}"
      shift 2
      ;;
    --expected-build-id)
      EXPECTED_BUILD_ID="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_URL" ]]; then
  APP_URL="$("$SCRIPT_DIR/confirm-public-url.sh")"
  APP_URL="${APP_URL%/}"
fi

probe_url="${APP_URL}/api/build-info"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

wait_for_container_running() {
  if ! command -v oci >/dev/null 2>&1 || ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi
  if [[ ! -d "$TF_DIR" ]]; then
    return 0
  fi

  local instance_ocid container_ocid details exit_code restarts elapsed=0 limit=120
  instance_ocid="$(cloud_store_tf_output container_instance_ocid 2>/dev/null || true)"
  if [[ -z "$instance_ocid" ]]; then
    return 0
  fi

  container_ocid="$(oci container-instances container-instance list-containers \
    --container-instance-id "$instance_ocid" \
    --query 'data.items[0].id' \
    --raw-output 2>/dev/null || true)"
  if [[ -z "$container_ocid" || "$container_ocid" == "null" ]]; then
    return 0
  fi

  echo "Waiting for OCI container to reach CONTAINER_RUNNING (up to ${limit}s)..." >&2
  while (( elapsed < limit )); do
    details="$(oci container-instances container get \
      --container-id "$container_ocid" \
      --query 'data."lifecycle-details"' \
      --raw-output 2>/dev/null || true)"
    if [[ "$details" == "CONTAINER_RUNNING" ]]; then
      echo "Container is running." >&2
      return 0
    fi
    if [[ "$details" == "CONTAINER_TERMINATED" ]]; then
      exit_code="$(oci container-instances container get \
        --container-id "$container_ocid" \
        --query 'data."exit-code"' \
        --raw-output 2>/dev/null || true)"
      restarts="$(oci container-instances container get \
        --container-id "$container_ocid" \
        --query 'data."container-restart-attempt-count"' \
        --raw-output 2>/dev/null || true)"
      if [[ -n "$exit_code" && "$exit_code" != "0" && "$exit_code" != "null" ]]; then
        echo "error: container exited (code=${exit_code}, restarts=${restarts:-?}) — check OCI container logs" >&2
        return 1
      fi
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  echo "warn: container not CONTAINER_RUNNING after ${limit}s; continuing HTTP probe" >&2
  return 0
}

wait_for_container_running || exit 1

echo "Waiting for GET ${probe_url} → 200 (up to ${TIMEOUT_SEC}s)..." >&2
elapsed=0
while (( elapsed < TIMEOUT_SEC )); do
  http_code="$(curl -sk --max-time 8 -o "$body_file" -w "%{http_code}" "$probe_url" || true)"
  if [[ "$http_code" == "200" ]]; then
    if [[ -n "$EXPECTED_BUILD_ID" ]]; then
      if ! grep -q "\"buildId\":\"${EXPECTED_BUILD_ID}\"" "$body_file"; then
        echo "  ... ${elapsed}s: HTTP 200 but buildId not ${EXPECTED_BUILD_ID} yet" >&2
        sleep "$INTERVAL_SEC"
        elapsed=$((elapsed + INTERVAL_SEC))
        continue
      fi
    fi
    cat "$body_file"
    echo "" >&2
    echo "ok: GET ${probe_url} → 200" >&2
    exit 0
  fi

  if [[ "$http_code" == "502" || "$http_code" == "503" || "$http_code" == "000" ]]; then
    echo "  ... ${elapsed}s: HTTP ${http_code} (LB backend still starting)" >&2
  else
    echo "  ... ${elapsed}s: HTTP ${http_code}" >&2
  fi
  sleep "$INTERVAL_SEC"
  elapsed=$((elapsed + INTERVAL_SEC))
done

echo "error: timed out after ${TIMEOUT_SEC}s waiting for ${probe_url}" >&2
echo "hint: oci container-instances container get --container-id <id> --query 'data.{exit:\"exit-code\",state:\"lifecycle-details\"}'" >&2
exit 1
