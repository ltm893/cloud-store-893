#!/usr/bin/env bash
# Compatibility wrapper — use scripts/db/migrate/migrate-login-approval-till.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/db/migrate/migrate-login-approval-till.sh" "$@"
