#!/usr/bin/env bash
# Compatibility wrapper — use scripts/dev/adb-wifi.sh
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev/adb-wifi.sh" "$@"
