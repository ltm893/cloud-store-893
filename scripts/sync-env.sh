#!/usr/bin/env bash
# Compatibility wrapper — use scripts/dev/sync-env.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev/sync-env.sh" "$@"
