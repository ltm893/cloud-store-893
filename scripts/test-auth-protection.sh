#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-auth-protection.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-auth-protection.sh" "$@"
