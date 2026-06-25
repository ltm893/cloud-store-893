#!/usr/bin/env bash
# Add OAuth redirect URIs for the dev hostname (keeps prod URIs intact).
#
#   export IDP_DOMAIN_ENDPOINT="https://idcs-....identity.us-ashburn-1.oci.oraclecloud.com"
#   ./scripts/oci/idp-update-redirect-uris-dev.sh

set -euo pipefail

export APP_PUBLIC_HOST="${APP_PUBLIC_HOST:-dev.oci.cloudstore893.com}"
export APP_PUBLIC_SCHEME="${APP_PUBLIC_SCHEME:-https}"
export APP_PUBLIC_PORT="${APP_PUBLIC_PORT:-}"

exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/idp-update-redirect-uris.sh"
