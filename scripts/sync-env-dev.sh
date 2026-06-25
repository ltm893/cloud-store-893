#!/usr/bin/env bash
# Compatibility wrapper — use scripts/dev/sync-env-dev.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev/sync-env-dev.sh" "$@"
