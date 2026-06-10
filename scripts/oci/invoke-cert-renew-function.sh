#!/usr/bin/env bash
# Invoke the cert-renew OCI Function.
#
# Usage:
#   ./scripts/oci/invoke-cert-renew-function.sh --smoke-test  # fast: state + certbot + plugin
#   ./scripts/oci/invoke-cert-renew-function.sh --dry-run
#   ./scripts/oci/invoke-cert-renew-function.sh --force-renew   # POC only
#   ./scripts/oci/invoke-cert-renew-function.sh                 # normal renew (no-op until ~30d before expiry)

set -euo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/terraform"

DRY_RUN=false
FORCE_RENEW=false
SMOKE_TEST=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force-renew) FORCE_RENEW=true ;;
    --smoke-test) SMOKE_TEST=true ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "error: unknown arg: $arg" >&2; exit 2 ;;
  esac
done

FN_OCID="$(cd "$TF_DIR" && terraform output -raw cert_renew_function_ocid)"
if [[ -z "$FN_OCID" || "$FN_OCID" == "null" ]]; then
  echo "error: cert_renew_function_ocid missing — enable_cert_renew_function and terraform apply" >&2
  exit 1
fi

BODY='{}'
if [[ "$DRY_RUN" == true || "$FORCE_RENEW" == true || "$SMOKE_TEST" == true ]]; then
  BODY=$(DRY_RUN="$DRY_RUN" FORCE_RENEW="$FORCE_RENEW" SMOKE_TEST="$SMOKE_TEST" python3 -c '
import json, os
print(json.dumps({
    "dry_run": os.environ["DRY_RUN"] == "true",
    "force_renew": os.environ["FORCE_RENEW"] == "true",
    "smoke_test": os.environ["SMOKE_TEST"] == "true",
}))
')
fi

OUT="/tmp/cert-renew-invoke-$$.json"
echo "==> Invoking $FN_OCID (body=$BODY)"
oci fn function invoke \
  --function-id "$FN_OCID" \
  --body "$BODY" \
  --file "$OUT"

echo ""
cat "$OUT"
echo ""
rm -f "$OUT"
