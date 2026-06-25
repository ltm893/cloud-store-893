#!/usr/bin/env bash
# Compatibility wrapper — use scripts/db/reset-db.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db/reset-db.sh" "$@"
