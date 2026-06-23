#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-supervisor-routes.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-supervisor-routes.sh" "$@"
