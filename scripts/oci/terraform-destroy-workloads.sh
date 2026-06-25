#!/usr/bin/env bash
# Destroy every Terraform-managed resource in state except:
#   - data.* (data sources are not destroyed)
#   - oci_identity_compartment.main (long-lived compartment; lifecycle.prevent_destroy)
#
# Targets are derived from `terraform state list`, so new root or module resources
# are included automatically without editing this script.
#
# Usage (from repo root):
#   ./scripts/oci/terraform-destroy-workloads.sh           # prod — prompts: type yes
#   ./scripts/oci/terraform-destroy-workloads-dev.sh       # dev workloads
#   ./scripts/oci/terraform-destroy-workloads.sh --yes     # non-interactive
#   ./scripts/oci/terraform-destroy-workloads.sh --plan-only   # terraform plan -destroy only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"
TF_DIR="$CLOUD_STORE_TF_DIR"

AUTO_YES=0
PLAN_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --yes | -y) AUTO_YES=1 ;;
    --plan-only | -n) PLAN_ONLY=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--yes] [--plan-only]" >&2
      exit 1
      ;;
  esac
done

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not found on PATH." >&2
  exit 1
fi

if [[ ! -d "$TF_DIR" ]]; then
  echo "Expected terraform directory at: $TF_DIR" >&2
  exit 1
fi

cd "$TF_DIR"

if [[ ! -d .terraform ]]; then
  echo "Run: cd terraform && terraform init" >&2
  exit 1
fi

# Long-lived compartment in this repo (never pass to destroy).
# Match root and module addresses, e.g. oci_identity_compartment.main or module.x.oci_identity_compartment.main[0]
exclude_compartment='(\.|^)oci_identity_compartment\.main(\[|$)'

set +e
raw_list=$(terraform -chdir="$CLOUD_STORE_TF_DIR" state list -state="$CLOUD_STORE_TF_STATE" 2>/dev/null)
list_ec=$?
set -e
if [[ "$list_ec" -ne 0 ]]; then
  echo "terraform state list failed (init state? corrupted state?). Exit code: $list_ec" >&2
  exit 1
fi

workload_addrs=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  # Data sources are refreshed, not destroyed as state "resources" in the same way;
  # never pass them to -target destroy.
  [[ "$line" == data.* ]] && continue
  if printf '%s\n' "$line" | grep -Eq "$exclude_compartment"; then
    continue
  fi
  workload_addrs+=("$line")
done <<<"$raw_list"

if [[ "${#workload_addrs[@]}" -eq 0 ]]; then
  echo "No workload addresses in Terraform state (empty state, or only the compartment remains)."
  exit 0
fi

echo "Environment:         $(cloud_store_env_label)"
echo "Terraform state:     $CLOUD_STORE_TF_STATE"
echo "Terraform directory: $TF_DIR"
echo ""
echo "Addresses to destroy (${#workload_addrs[@]}):"
printf '  %s\n' "${workload_addrs[@]}"
echo ""
echo "Excluded from destroy:"
echo "  - data.* (data sources)"
echo "  - oci_identity_compartment.main (compartment kept in OCI)"
echo ""

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  echo "Running: terraform plan -destroy ($(cloud_store_env_label); no changes applied)"
  tf_cmd=(cloud_store_tf plan -destroy -no-color)
  for addr in "${workload_addrs[@]}"; do
    tf_cmd+=(-target="$addr")
  done
  "${tf_cmd[@]}"
  exit 0
fi

if [[ "$AUTO_YES" -ne 1 ]]; then
  read -r -p "Type yes to run terraform destroy: " reply
  lc=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
  if [[ "$lc" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Running: terraform destroy -auto-approve ($(cloud_store_env_label); scoped to listed addresses only)"
tf_cmd=(cloud_store_tf destroy -auto-approve -compact-warnings -no-color)
for addr in "${workload_addrs[@]}"; do
  tf_cmd+=(-target="$addr")
done
"${tf_cmd[@]}"
