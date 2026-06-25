#!/usr/bin/env bash
# Compatibility wrapper — use scripts/db/truncate-shift-auth-tables.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db/truncate-shift-auth-tables.sh" "$@"
