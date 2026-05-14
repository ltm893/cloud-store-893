#!/bin/zsh
# scripts/list-resources.sh
#
# Lists all OCI resources in the project compartment (default: cloud-store; matches Terraform project_name).
# Override: CLOUD_STORE_COMPARTMENT_NAME=my-name ./scripts/list-resources.sh
# Run this before deleting to see what exists, or after to confirm it's empty.
#
# Usage:
#   ./scripts/list-resources.sh              # search by compartment name
#   ./scripts/list-resources.sh <OCID>       # search by known compartment OCID

set -e

COMPARTMENT_NAME="${CLOUD_STORE_COMPARTMENT_NAME:-cloud-store}"

# ── Resolve compartment OCID ──────────────────────────────────────────────────
if [[ -n "$1" ]]; then
  COMPARTMENT_OCID="$1"
  echo "🔍 Using provided OCID: ${COMPARTMENT_OCID}"
else
  echo "🔍 Looking up compartment '${COMPARTMENT_NAME}'..."
  COMPARTMENT_OCID=$(oci iam compartment list \
    --all \
    --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null)

  if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
    echo "✅ Compartment '${COMPARTMENT_NAME}' not found — already deleted."
    exit 0
  fi

  echo "✅ Found: ${COMPARTMENT_OCID}"
fi

# ── Search all resources in that compartment ──────────────────────────────────
echo ""
echo "📦 Resources in '${COMPARTMENT_NAME}':"
echo "────────────────────────────────────────"

RESULTS=$(oci search resource structured-search \
  --query-text "query all resources where compartmentId = '${COMPARTMENT_OCID}'" \
  --query "data.items[*].{type:\"resource-type\", name:\"display-name\", state:\"lifecycle-state\", id:identifier}" \
  2>/dev/null)

COUNT=$(echo "$RESULTS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")

if [[ "$COUNT" == "0" || -z "$RESULTS" ]]; then
  echo "✅ No resources found — compartment is empty."
else
  echo "$RESULTS" | python3 -c "
import sys, json
items = json.load(sys.stdin)
for r in items:
    print(f\"  {r.get('type','?'):<45} {r.get('state','?'):<20} {r.get('name','?')}\")
print()
print(f'Total: {len(items)} resource(s)')
"
fi

echo ""
