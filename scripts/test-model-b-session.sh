#!/usr/bin/env bash
# Compatibility wrapper — use scripts/test/test-model-b-session.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test/test-model-b-session.sh" "$@"
