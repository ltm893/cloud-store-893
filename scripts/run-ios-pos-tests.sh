#!/usr/bin/env bash
# Compatibility wrapper — use scripts/ios/run-pos-tests.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios/run-pos-tests.sh" "$@"
