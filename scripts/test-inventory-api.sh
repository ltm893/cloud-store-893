#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-inventory-api.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-inventory-api.sh" "$@"
