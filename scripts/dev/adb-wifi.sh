#!/usr/bin/env bash
# adb-wifi.sh
#
# Helper for Android tablet ADB over Wi-Fi.
#
# Usage:
#   scripts/adb-wifi.sh status
#   scripts/adb-wifi.sh connect <tablet-ip> [port]
#   scripts/adb-wifi.sh usb-to-wifi <tablet-ip> [port]
#   scripts/adb-wifi.sh reconnect <tablet-ip> [port]
#   scripts/adb-wifi.sh disconnect [<tablet-ip> [port]]
#
# Examples:
#   scripts/adb-wifi.sh connect 192.168.1.42
#   scripts/adb-wifi.sh usb-to-wifi 192.168.1.42

set -euo pipefail

ADB="${ADB:-adb}"
DEFAULT_PORT="${ADB_WIFI_PORT:-5555}"

usage() {
  cat <<'EOF'
Usage:
  scripts/adb-wifi.sh status
  scripts/adb-wifi.sh connect <tablet-ip> [port]
  scripts/adb-wifi.sh usb-to-wifi <tablet-ip> [port]
  scripts/adb-wifi.sh reconnect <tablet-ip> [port]
  scripts/adb-wifi.sh disconnect [<tablet-ip> [port]]
EOF
}

require_adb() {
  if ! command -v "$ADB" >/dev/null 2>&1; then
    echo "error: adb not found in PATH (or set ADB=/path/to/adb)" >&2
    exit 1
  fi
}

endpoint() {
  local ip="$1"
  local port="${2:-$DEFAULT_PORT}"
  printf '%s:%s' "$ip" "$port"
}

cmd_status() {
  "$ADB" devices -l
}

cmd_connect() {
  local ip="${1:-}"
  local port="${2:-$DEFAULT_PORT}"
  [[ -z "$ip" ]] && { usage; exit 1; }
  local ep
  ep="$(endpoint "$ip" "$port")"
  echo "==> adb connect $ep"
  "$ADB" connect "$ep"
  echo "==> adb devices"
  "$ADB" devices -l
}

cmd_usb_to_wifi() {
  local ip="${1:-}"
  local port="${2:-$DEFAULT_PORT}"
  [[ -z "$ip" ]] && { usage; exit 1; }
  echo "==> adb tcpip $port  (requires USB-connected, authorized device)"
  "$ADB" tcpip "$port"
  cmd_connect "$ip" "$port"
}

cmd_reconnect() {
  local ip="${1:-}"
  local port="${2:-$DEFAULT_PORT}"
  [[ -z "$ip" ]] && { usage; exit 1; }
  local ep
  ep="$(endpoint "$ip" "$port")"
  echo "==> adb disconnect $ep"
  "$ADB" disconnect "$ep" || true
  cmd_connect "$ip" "$port"
}

cmd_disconnect() {
  local ip="${1:-}"
  local port="${2:-$DEFAULT_PORT}"
  if [[ -n "$ip" ]]; then
    local ep
    ep="$(endpoint "$ip" "$port")"
    echo "==> adb disconnect $ep"
    "$ADB" disconnect "$ep"
  else
    echo "==> adb disconnect (all)"
    "$ADB" disconnect
  fi
  "$ADB" devices -l
}

require_adb

ACTION="${1:-status}"
shift || true

case "$ACTION" in
  status) cmd_status "$@" ;;
  connect) cmd_connect "$@" ;;
  usb-to-wifi) cmd_usb_to_wifi "$@" ;;
  reconnect) cmd_reconnect "$@" ;;
  disconnect) cmd_disconnect "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac

