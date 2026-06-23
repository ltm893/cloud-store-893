#!/usr/bin/env bash
# Compatibility wrapper — use scripts/ios/sync-portrait-resources.js
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/sync-portrait-resources.js" "$@"
