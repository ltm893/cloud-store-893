#!/usr/bin/env bash
# Compatibility wrapper — use scripts/dev/update-idp-redirects.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev/update-idp-redirects.sh" "$@"
