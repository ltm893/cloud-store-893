#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-api-curl.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-api-curl.sh" "$@"
