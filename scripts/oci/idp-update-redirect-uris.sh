#!/usr/bin/env bash
# Add OAuth callback redirect URIs to cloud-store-pos / cloud-store-admin apps.
#
# Prerequisites: OCI CLI configured (oci setup config), jq installed.
#
# Usage:
#   export IDP_DOMAIN_ENDPOINT="https://idcs-XXXX....us-ashburn-idcs-1.identity.us-ashburn-1.oci.oraclecloud.com"
#   (base domain URL only — do NOT append /admin/v1; the CLI adds it)
#   export APP_PUBLIC_HOST="oci.cloudstore893.com"   # no scheme
#   export APP_PUBLIC_SCHEME="https"                 # default http
#   export APP_PUBLIC_PORT=""                        # empty = omit port (443 for https)
#   ./scripts/oci/idp-update-redirect-uris.sh
#
# Find IDP_DOMAIN_ENDPOINT: OCI Console → Domains → cloud-store-apps →
#   Domain → cloud-store-apps → home-region-url (no :443), NOT .../admin/v1

set -euo pipefail

RAW_ENDPOINT="${IDP_DOMAIN_ENDPOINT:?Set IDP_DOMAIN_ENDPOINT (domain base URL)}"
# CLI appends /admin/v1 itself — strip if you already included it
ENDPOINT="${RAW_ENDPOINT%/admin/v1}"
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT%:443}"
HOST="${APP_PUBLIC_HOST:?Set APP_PUBLIC_HOST (e.g. oci.cloudstore893.com)}"
SCHEME="${APP_PUBLIC_SCHEME:-http}"
PORT="${APP_PUBLIC_PORT:-${APP_PORT:-3000}}"

port_suffix=""
if [[ -n "$PORT" ]]; then
  if [[ "$SCHEME" == "https" && "$PORT" == "443" ]] || [[ "$SCHEME" == "http" && "$PORT" == "80" ]]; then
    port_suffix=""
  else
    port_suffix=":${PORT}"
  fi
fi
BASE="${SCHEME}://${HOST}${port_suffix}"

add_redirects_for_app() {
  local name="$1"
  shift
  local -a new_uris=("$@")

  echo "==> Looking up app: ${name}"
  local filter
  filter=$(printf 'displayName eq "%s"' "$name")
  local app_id
  app_id=$(oci --region us-ashburn-1 identity-domains apps list \
    --endpoint "$ENDPOINT" \
    --filter "$filter" \
    --attributes id,displayName \
    --query 'data.resources[0].id' \
    --raw-output)

  if [[ -z "$app_id" || "$app_id" == "null" ]]; then
    echo "ERROR: App not found: ${name}" >&2
    exit 1
  fi

  echo "    App id: ${app_id}"

  local tmp existing add_json merged
  tmp=$(mktemp)
  oci --region us-ashburn-1 identity-domains app get \
    --endpoint "$ENDPOINT" \
    --app-id "$app_id" \
    >"$tmp"

  if ! jq -e '.data' "$tmp" >/dev/null 2>&1; then
    echo "ERROR: app get returned unexpected JSON for ${name}" >&2
    head -c 500 "$tmp" >&2 || true
    exit 1
  fi

  existing=$(jq -c '.data.redirectUris // [] | if type != "array" then [] else . end' "$tmp")
  add_json=$(printf '%s\n' "${new_uris[@]}" | jq -R '{value: .}' | jq -s '.')
  merged=$(jq -c --argjson existing "$existing" --argjson add "$add_json" \
    '$existing + $add | unique_by(.value)')

  local patch_ops
  patch_ops=$(jq -nc --argjson uris "$merged" \
    '[{op:"replace",path:"redirectUris",value:$uris}]')

  local schemas
  schemas='[{"value":"urn:ietf:params:scim:api:messages:2.0:PatchOp","type":"string"}]'

  echo "    Setting redirectUris:"
  echo "$merged" | jq -r '.[].value' | sed 's/^/      /'

  oci --region us-ashburn-1 identity-domains app patch \
    --endpoint "$ENDPOINT" \
    --app-id "$app_id" \
    --schemas "$schemas" \
    --operations "$patch_ops" \
    >/dev/null

  echo "    Done."
  rm -f "$tmp"
}

add_redirects_for_app "cloud-store-pos" \
  "${BASE}/" \
  "${BASE}/oauth/callback" \
  "http://127.0.0.1:${PORT}/" \
  "http://127.0.0.1:${PORT}/oauth/callback"

add_redirects_for_app "cloud-store-admin" \
  "${BASE}/admin/" \
  "${BASE}/oauth/admin/callback" \
  "http://127.0.0.1:${PORT}/admin/" \
  "http://127.0.0.1:${PORT}/oauth/admin/callback"

echo ""
echo "Verify in Console → Integrated applications → OAuth configuration → Redirect URL"
