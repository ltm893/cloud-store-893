#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-cashier-approval-poll.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-cashier-approval-poll.sh" "$@"
