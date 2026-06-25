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

OCI_REGION="${OCI_REGION:-us-ashburn-1}"

RAW_ENDPOINT="${IDP_DOMAIN_ENDPOINT:?Set IDP_DOMAIN_ENDPOINT (domain base URL)}"
# CLI appends /admin/v1 itself — strip if you already included it
ENDPOINT="${RAW_ENDPOINT%/admin/v1}"
ENDPOINT="${ENDPOINT%/}"
ENDPOINT="${ENDPOINT%:443}"
HOST="${APP_PUBLIC_HOST:?Set APP_PUBLIC_HOST (e.g. oci.cloudstore893.com)}"
SCHEME="${APP_PUBLIC_SCHEME:-http}"
LOCAL_PORT="${APP_PORT:-3000}"

port_suffix=""
if [[ -n "${APP_PUBLIC_PORT:-}" ]]; then
  if [[ "$SCHEME" == "https" && "$APP_PUBLIC_PORT" == "443" ]] \
    || [[ "$SCHEME" == "http" && "$APP_PUBLIC_PORT" == "80" ]]; then
    port_suffix=""
  else
    port_suffix=":${APP_PUBLIC_PORT}"
  fi
  LOCAL_PORT="$APP_PUBLIC_PORT"
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
  app_id=$(oci --region "$OCI_REGION" identity-domains apps list \
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

  local existing add_json merged
  echo "    Reading current redirect URIs..."
  existing=$(oci --region "$OCI_REGION" identity-domains apps list \
    --endpoint "$ENDPOINT" \
    --filter "$filter" \
    --attributes redirectUris \
    --query 'data.resources[0]."redirect-uris"' \
    --raw-output 2>/dev/null || true)
  [[ -n "$existing" && "$existing" != "null" ]] || existing='[]'
  existing=$(jq -c 'if type != "array" then [] else . end | map(if type == "string" then . elif type == "object" then (.value // empty) else empty end) | map(select(length > 0))' <<<"$existing")
  add_json=$(printf '%s\n' "${new_uris[@]}" | jq -R 'select(length > 0)' | jq -s .)
  merged=$(
    {
      jq -r '.[]?' <<<"$existing"
      jq -r '.[]?' <<<"$add_json"
    } | sort -u | jq -R . | jq -s .
  )

  local patch_ops
  patch_ops=$(jq -nc --argjson uris "$merged" \
    '[{op:"replace",path:"redirectUris",value:$uris}]')

  local schemas
  schemas='[{"value":"urn:ietf:params:scim:api:messages:2.0:PatchOp","type":"string"}]'

  echo "    Setting redirectUris:"
  echo "$merged" | jq -r '.[]' | sed 's/^/      /'

  echo "    Patching app..."
  oci --region "$OCI_REGION" identity-domains app patch \
    --endpoint "$ENDPOINT" \
    --app-id "$app_id" \
    --schemas "$schemas" \
    --operations "$patch_ops" \
    >/dev/null

  echo "    Done."
}

# Optional extra hosts for local dev (space-separated): LAN IP, etc.
#   EXTRA_REDIRECT_HOSTS="10.0.0.122" ./scripts/oci/idp-update-redirect-uris.sh
POS_EXTRA=()
ADMIN_EXTRA=()
LOCAL_HOSTS=(127.0.0.1 localhost)
if [[ -n "${EXTRA_REDIRECT_HOSTS:-}" ]]; then
  read -r -a _extra <<< "${EXTRA_REDIRECT_HOSTS}"
  LOCAL_HOSTS+=("${_extra[@]}")
fi
for host in "${LOCAL_HOSTS[@]}"; do
  [[ -z "$host" ]] && continue
  POS_EXTRA+=("http://${host}:${LOCAL_PORT}/" "http://${host}:${LOCAL_PORT}/oauth/callback")
  ADMIN_EXTRA+=("http://${host}:${LOCAL_PORT}/admin/" "http://${host}:${LOCAL_PORT}/oauth/admin/callback")
done

add_redirects_for_app "cloud-store-pos" \
  "${BASE}/" \
  "${BASE}/oauth/callback" \
  "${POS_EXTRA[@]}"

add_redirects_for_app "cloud-store-admin" \
  "${BASE}/admin/" \
  "${BASE}/oauth/admin/callback" \
  "${ADMIN_EXTRA[@]}"

echo ""
echo "Verify in Console → Integrated applications → OAuth configuration → Redirect URL"
