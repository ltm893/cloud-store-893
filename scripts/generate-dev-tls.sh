#!/usr/bin/env bash
# Compatibility wrapper — use scripts/tls/generate-dev-tls.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tls/generate-dev-tls.sh" "$@"
