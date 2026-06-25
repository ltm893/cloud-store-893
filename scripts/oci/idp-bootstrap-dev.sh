#!/usr/bin/env bash
# Compatibility wrapper — use scripts/oci/idp/bootstrap-dev.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/idp/bootstrap-dev.sh" "$@"
