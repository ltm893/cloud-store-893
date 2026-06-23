#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-login-approval-lib.js
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-login-approval-lib.js" "$@"
