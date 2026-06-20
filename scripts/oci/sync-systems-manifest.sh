#!/usr/bin/env bash
# Writes data/systems-oci-resources.json from OCI Resource Search + Terraform outputs.
#
# Usage:
#   ./scripts/oci/sync-systems-manifest.sh
#
# Run before docker build / redeploy so the Systems tab shows live OCI inventory.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$PROJECT_ROOT/data/systems-oci-resources.json"
TF_DIR="$PROJECT_ROOT/terraform"
COMPARTMENT_NAME="${CLOUD_STORE_COMPARTMENT_NAME:-cloud-store}"

if ! command -v oci >/dev/null 2>&1; then
  echo "error: oci CLI not found" >&2
  exit 1
fi

COMPARTMENT_OCID="${1:-}"
if [[ -z "$COMPARTMENT_OCID" ]]; then
  if [[ -d "$TF_DIR" ]] && command -v terraform >/dev/null 2>&1; then
    COMPARTMENT_OCID="$(cd "$TF_DIR" && terraform output -raw compartment_ocid 2>/dev/null || true)"
  fi
fi
if [[ -z "$COMPARTMENT_OCID" ]]; then
  COMPARTMENT_OCID="$(oci iam compartment list \
    --all \
    --query "data[?name=='${COMPARTMENT_NAME}'].id | [0]" \
    --raw-output 2>/dev/null || true)"
fi
if [[ -z "$COMPARTMENT_OCID" || "$COMPARTMENT_OCID" == "null" ]]; then
  echo "error: could not resolve compartment OCID" >&2
  exit 1
fi

REGION="$(oci iam region list --query 'data[?is-home-region==\`true\`].name | [0]' --raw-output 2>/dev/null || true)"
if [[ -z "$REGION" || "$REGION" == "null" ]]; then
  REGION="${OCI_REGION:-us-ashburn-1}"
fi

echo "==> Compartment: $COMPARTMENT_OCID"
echo "==> Region: $REGION"

ITEMS_JSON="$(oci search resource structured-search \
  --query-text "query all resources where compartmentId = '${COMPARTMENT_OCID}'" \
  --query 'data.items[*].{"type":"resource-type","name":"display-name","state":"lifecycle-state","id":identifier}' \
  2>/dev/null || echo '[]')"

mkdir -p "$(dirname "$OUT")"

ITEMS_JSON="$ITEMS_JSON" python3 - "$OUT" "$COMPARTMENT_NAME" "$REGION" "$COMPARTMENT_OCID" <<'PY'
import json, os, sys
from datetime import datetime, timezone

out_path, compartment, region, compartment_ocid = sys.argv[1:5]
raw = os.environ.get("ITEMS_JSON", "[]")
try:
    items = json.loads(raw) if raw else []
except json.JSONDecodeError:
    items = []

resources = []
for row in items:
    resources.append({
        "type": row.get("type") or "—",
        "name": row.get("name") or "—",
        "state": row.get("state") or "—",
        "id": row.get("id"),
    })

payload = {
    "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "compartment": compartment,
    "compartmentOcid": compartment_ocid,
    "region": region,
    "resources": resources,
    "source": "oci-search",
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")

print(f"wrote {len(resources)} resource(s) to {out_path}")
PY
