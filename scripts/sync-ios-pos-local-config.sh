#!/usr/bin/env bash
# Compatibility wrapper — use scripts/ios/sync-pos-local-config.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/sync-pos-local-config.sh" "$@"
