#!/usr/bin/env bash
# Compatibility wrapper — use scripts/ios/sync-local-config.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/sync-local-config.sh" "$@"
