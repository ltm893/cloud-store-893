#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/run-integration-tests.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/run-integration-tests.sh" "$@"
