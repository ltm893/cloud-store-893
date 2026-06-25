#!/usr/bin/env bash
# Compatibility wrapper — use scripts/tools/install-sqlcl.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/install-sqlcl.sh" "$@"
