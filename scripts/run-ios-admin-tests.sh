#!/usr/bin/env bash
# Compatibility wrapper — use scripts/ios/run-admin-tests.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/run-admin-tests.sh" "$@"
