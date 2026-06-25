#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/create-test-pending-approval.js
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/create-test-pending-approval.js" "$@"
