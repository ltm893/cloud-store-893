#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/seed-test-sales-matrix.js
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/seed-test-sales-matrix.js" "$@"
