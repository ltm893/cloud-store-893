#!/usr/bin/env bash
# Register local dev OAuth redirect URIs (LAN IP + localhost) in Oracle IDCS.
#
# Prerequisites: OCI CLI + jq; IDP_DOMAIN_ENDPOINT in env or .env
#
# Usage:
#   ./scripts/dev-update-idp-redirects.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
[[ -f "${ROOT}/.env" ]] && source "${ROOT}/.env"

LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
PORT="${APP_PORT:-${PORT:-3000}}"

if [[ -z "${IDP_DOMAIN_ENDPOINT:-}" ]]; then
  echo "Set IDP_DOMAIN_ENDPOINT (see docs/idp-setup.md)" >&2
  exit 1
fi

HOSTS="localhost"
[[ -n "$LAN_IP" ]] && HOSTS="${LAN_IP} ${HOSTS}"

export APP_PUBLIC_HOST="${LAN_IP:-127.0.0.1}"
export APP_PUBLIC_SCHEME="http"
export APP_PUBLIC_PORT="${PORT}"
export EXTRA_REDIRECT_HOSTS="${HOSTS}"

echo "==> Updating IdCS redirects for local dev"
echo "    BASE=http://${APP_PUBLIC_HOST}:${PORT}"
echo "    EXTRA_REDIRECT_HOSTS=${EXTRA_REDIRECT_HOSTS}"

"${ROOT}/scripts/oci/idp-update-redirect-uris.sh"

echo ""
echo "Tablet OAuth callback: http://${LAN_IP:-?}:${PORT}/oauth/callback"
echo "Admin OAuth callback:  http://127.0.0.1:${PORT}/oauth/admin/callback (use 127.0.0.1, not localhost, unless both registered)"
