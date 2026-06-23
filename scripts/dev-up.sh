#!/usr/bin/env bash
# Compatibility wrapper — use scripts/dev/up.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev/up.sh" "$@"
