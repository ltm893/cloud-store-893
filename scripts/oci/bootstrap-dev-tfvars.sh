#!/usr/bin/env bash
# Copy OCI auth + namespace from prod terraform.tfvars into terraform.dev.tfvars.
#
# Keeps dev-specific values (project_name, adb_db_name, lb hostname, etc.).
# You still must set a unique adb_admin_password in terraform.dev.tfvars.
#
# Usage:
#   ./scripts/oci/bootstrap-dev-tfvars.sh
#   ./scripts/oci/bootstrap-dev-tfvars.sh --dry-run

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROD_TFVARS="$PROJECT_ROOT/terraform/terraform.tfvars"
DEV_TFVARS="$PROJECT_ROOT/terraform/terraform.dev.tfvars"
EXAMPLE="$PROJECT_ROOT/terraform/terraform.dev.tfvars.example"

DRY=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY=1

SHARED_KEYS=(
  tenancy_ocid
  user_ocid
  fingerprint
  private_key_path
  region
  object_storage_namespace
  ocir_region_key
)

[[ -f "$PROD_TFVARS" ]] || {
  echo "error: $PROD_TFVARS not found — deploy prod stack first or create prod tfvars" >&2
  exit 1
}

if [[ ! -f "$DEV_TFVARS" ]]; then
  cp "$EXAMPLE" "$DEV_TFVARS"
  echo "Created $DEV_TFVARS from example"
fi

replace_key_in_dev() {
  local key="$1"
  local line
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$PROD_TFVARS" | head -1 || true)"
  if [[ -z "$line" ]]; then
    echo "warn: ${key} not found in $PROD_TFVARS" >&2
    return 0
  fi
  line="${line%%$'\r'}"
  if [[ "$DRY" -eq 1 ]]; then
    echo "would set: $line"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$DEV_TFVARS"; then
    awk -v key="$key" -v line="$line" '
      $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { print line; next }
      { print }
    ' "$DEV_TFVARS" >"$tmp"
  else
    cp "$DEV_TFVARS" "$tmp"
    printf '\n%s\n' "$line" >>"$tmp"
  fi
  mv "$tmp" "$DEV_TFVARS"
}

for key in "${SHARED_KEYS[@]}"; do
  replace_key_in_dev "$key"
done

if [[ "$DRY" -eq 1 ]]; then
  echo "Dry run complete."
  exit 0
fi

echo "Updated $DEV_TFVARS from prod auth/namespace keys."
echo ""
echo "Next:"
echo "  1. Edit adb_admin_password in $DEV_TFVARS (must differ from prod)"
echo "  2. ./scripts/oci/deploy-dev.sh"
