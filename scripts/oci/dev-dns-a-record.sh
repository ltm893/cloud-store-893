#!/usr/bin/env bash
# Add or update dev.oci.cloudstore893.com A record in the existing OCI DNS zone.
#
# Uses domain patch (not zone update) so SOA/NS records in the zone are untouched.
#
# Prerequisite: dev load balancer deployed (enable_load_balancer = true).
#
#   CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh
#   CLOUD_STORE_ENV=dev ./scripts/oci/dev-dns-a-record.sh --dry-run

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/terraform-env.sh
source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
cloud_store_resolve_tf_env "$PROJECT_ROOT"

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1 ;;
  esac
done

command -v oci >/dev/null 2>&1 || { echo "error: oci CLI required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq required (brew install jq)" >&2; exit 1; }

LB_IP="$(cloud_store_tf_output load_balancer_public_ip || true)"
LB_IP="${LB_IP//$'\n'/}"
if [[ -z "$LB_IP" || "$LB_IP" == "null" ]]; then
  echo "error: load_balancer_public_ip is empty — run ./scripts/oci/deploy-dev.sh first" >&2
  exit 1
fi
if ! [[ "$LB_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: load_balancer_public_ip is not a valid IPv4 address (got: ${LB_IP})" >&2
  echo "hint: complete ./scripts/oci/deploy-dev.sh before creating the DNS record" >&2
  exit 1
fi

ZONE="oci.cloudstore893.com"
RECORD="dev.oci.cloudstore893.com"

echo "Environment: $CLOUD_STORE_ENV"
echo "Zone:        $ZONE"
echo "Record:      $RECORD → A $LB_IP (TTL 300)"
echo ""

EXISTING_JSON="$(oci dns record rrset get \
  --zone-name-or-id "$ZONE" \
  --domain "$RECORD" \
  --rtype A \
  --query 'data.items' \
  2>/dev/null || echo '[]')"

PATCH_ITEMS="$(jq -nc \
  --arg domain "$RECORD" \
  --arg ip "$LB_IP" \
  --argjson existing "$EXISTING_JSON" \
  '
  ($existing // []) as $rows |
  ($rows | map(.rdata)) as $current |
  (if ($current | index($ip)) then [] else
    ($rows | map(select(.rdata != $ip)) | map({
      operation: "REMOVE",
      domain: $domain,
      rtype: "A",
      rdata: .rdata
    }))
  end) as $removes |
  (if ($current | index($ip)) then [] else [{
    operation: "ADD",
    domain: $domain,
    rtype: "A",
    ttl: 300,
    rdata: $ip
  }] end) as $adds |
  $removes + $adds
')"

if [[ "$PATCH_ITEMS" == "[]" ]]; then
  echo "No change — A record already points to ${LB_IP}"
  exit 0
fi

echo "Patch operations:"
echo "$PATCH_ITEMS" | jq -r '.[] | "  \(.operation) \(.rtype) \(.rdata // "")"'
echo ""

if [[ "$DRY" -eq 1 ]]; then
  echo "Dry run — would run: oci dns record domain patch"
  exit 0
fi

oci dns record domain patch \
  --zone-name-or-id "$ZONE" \
  --domain "$RECORD" \
  --items "$PATCH_ITEMS"

echo ""
echo "Verify:"
echo "  dig A ${RECORD} +short @8.8.8.8"
echo "  curl -s -o /dev/null -w '%{http_code}\\n' http://${LB_IP}:3000/api/build-info"
