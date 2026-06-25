#!/usr/bin/env bash
# List OCI resources in the project compartment (prod or dev).
#
# Usage:
#   ./scripts/oci/list-resources.sh              # prompt: prod or dev
#   ./scripts/oci/list-resources.sh --prod
#   ./scripts/oci/list-resources.sh --dev
#   CLOUD_STORE_ENV=dev ./scripts/oci/list-resources.sh
#   ./scripts/oci/list-resources.sh <compartment-ocid>
#
# Compartment OCID comes from terraform state when available; otherwise looks up
# project_name from the environment's terraform.*.tfvars (cloud-store / cloud-store-dev).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/terraform-env.sh
source "$SCRIPT_DIR/lib/terraform-env.sh"

PROVIDED_OCID=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --prod) export CLOUD_STORE_ENV=prod ;;
    --dev) export CLOUD_STORE_ENV=dev ;;
    -h|--help)
      usage
      exit 0
      ;;
    ocid1.compartment.*)
      PROVIDED_OCID="$arg"
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

list_resources_project_name() {
  local name=""
  if [[ -f "${CLOUD_STORE_TFVARS:-}" ]]; then
    name="$(awk -F= '/^[[:space:]]*project_name[[:space:]]*=/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      gsub(/^"|"$/, "", $2)
      print $2
      exit
    }' "$CLOUD_STORE_TFVARS")"
  fi
  if [[ -n "$name" ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  case "${CLOUD_STORE_ENV:-prod}" in
    dev) printf '%s\n' "cloud-store-dev" ;;
    *) printf '%s\n' "cloud-store" ;;
  esac
}

list_resources_select_env() {
  if [[ -n "${CLOUD_STORE_ENV:-}" || -n "$PROVIDED_OCID" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    export CLOUD_STORE_ENV=prod
    return 0
  fi
  echo "Which environment?"
  echo "  1) prod  (cloud-store)"
  echo "  2) dev   (cloud-store-dev)"
  local choice
  read -r -p "Choice [1]: " choice
  case "${choice:-1}" in
    1|prod|p|P|"") export CLOUD_STORE_ENV=prod ;;
    2|dev|d|D) export CLOUD_STORE_ENV=dev ;;
    *)
      echo "Invalid choice: $choice" >&2
      exit 1
      ;;
  esac
}

list_resources_select_env
if [[ -z "$PROVIDED_OCID" ]]; then
  cloud_store_resolve_tf_env "$PROJECT_ROOT"
fi

COMPARTMENT_NAME="$(list_resources_project_name)"

# ── Resolve compartment OCID ──────────────────────────────────────────────────
if [[ -n "$PROVIDED_OCID" ]]; then
  COMPARTMENT_OCID="$PROVIDED_OCID"
  echo "Using provided compartment OCID: ${COMPARTMENT_OCID}"
elif COMPARTMENT_OCID="$(cloud_store_tf_output compartment_ocid)" && [[ -n "$COMPARTMENT_OCID" ]]; then
  echo "Environment: $(cloud_store_env_label)"
  echo "Compartment: ${COMPARTMENT_NAME} (from ${CLOUD_STORE_TF_STATE##*/})"
  echo "OCID:        ${COMPARTMENT_OCID}"
else
  echo "Environment: $(cloud_store_env_label)"
  echo "Looking up compartment '${COMPARTMENT_NAME}'..."
  COMPARTMENT_OCID="$(oci iam compartment list \
    --all \
    --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true)"

  if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
    echo "Compartment '${COMPARTMENT_NAME}' not found — already deleted or not deployed yet."
    exit 0
  fi

  echo "Found: ${COMPARTMENT_OCID}"
fi

# ── Search all resources in that compartment ──────────────────────────────────
echo ""
echo "Resources in '${COMPARTMENT_NAME}':"
echo "────────────────────────────────────────"

RESULTS="$(oci search resource structured-search \
  --query-text "query all resources where compartmentId = '${COMPARTMENT_OCID}'" \
  --query "data.items[*].{type:\"resource-type\", name:\"display-name\", state:\"lifecycle-state\", id:identifier}" \
  2>/dev/null || true)"

COUNT="$(echo "$RESULTS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")"

if [[ "$COUNT" == "0" || -z "$RESULTS" ]]; then
  echo "No resources found — compartment is empty."
else
  echo "$RESULTS" | python3 -c "
import sys, json
items = json.load(sys.stdin)
for r in items:
    r_type = r.get('type') or '?'
    r_state = r.get('state') or '?'
    r_name = r.get('name') or '?'
    print(f\"  {r_type:<45} {r_state:<20} {r_name}\")
print()
print(f'Total: {len(items)} resource(s)')
"
fi

echo ""
