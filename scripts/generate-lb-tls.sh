#!/usr/bin/env bash
# Compatibility wrapper — use scripts/tls/generate-lb-tls.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tls/generate-lb-tls.sh" "$@"
