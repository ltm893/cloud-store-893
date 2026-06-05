#!/usr/bin/env zsh
# Remove Terraform *workload* addresses from state (VCN, ADB, container, OCIR repo).
# The compartment (oci_identity_compartment.main) is NEVER removed — one stable
# compartment `cloud-store` (see var.project_name) is always kept in state and in OCI.
#
# Use when child resources are stuck or orphaned in state; then re-apply workloads:
#   ./scripts/oci/terraform-recover-workload-state.sh
#   cd terraform && terraform plan && terraform apply
#
# Does not delete anything in OCI (state-only). Does not touch the compartment resource.

set -e

SCRIPT_DIR="${0:a:h}"
TF_DIR="${SCRIPT_DIR}/../../terraform"

if [[ ! -d "$TF_DIR" ]]; then
  echo "❌ Expected terraform/ at ${TF_DIR}"
  exit 1
fi

cd "$TF_DIR" || exit 1

echo "Current Terraform state (oci_* resources):"
terraform state list 2>/dev/null | grep '^oci_' || echo "  (none or not initialized)"
echo ""
echo "This removes workload resources from Terraform STATE only."
echo "The compartment resource oci_identity_compartment.main is NOT modified."
echo ""
printf "Type the word yes to continue: "
read -r reply
[[ "${reply:l}" == "yes" ]] || { echo "Aborted."; exit 1; }

# Children first; compartment intentionally omitted.
STATE_ADDRS=(
  oci_container_instances_container_instance.main
  oci_database_autonomous_database.main
  oci_core_subnet.main
  oci_core_security_list.main
  oci_core_route_table.main
  oci_core_internet_gateway.main
  oci_core_vcn.main
  oci_artifacts_container_repository.main
)

for addr in "${STATE_ADDRS[@]}"; do
  if terraform state show "$addr" &>/dev/null; then
    echo "  state rm $addr"
    terraform state rm "$addr"
  else
    echo "  (skip, not in state: $addr)"
  fi
done

echo ""
echo "✅ Workload addresses removed from state (compartment unchanged)."
echo "Next: cd ${TF_DIR} && terraform plan && terraform apply"
echo "      or from repo root: ./scripts/oci/deploy.sh"
