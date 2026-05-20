#!/usr/bin/env bash
# RebuildReinstall.sh — Build debug APK and install on a connected tablet/emulator.
#
# Usage (from android-pos/):
#   ./RebuildReinstall.sh
#
# Optional env:
#   LAN_IP=192.168.1.10   Override Mac LAN IP baked into API_BASE_URL
#   ADB=adb               Path to adb if not on PATH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ADB="${ADB:-adb}"
APK="app/build/outputs/apk/debug/app-debug.apk"

detect_lan_ip() {
  if [[ -n "${LAN_IP:-}" ]]; then
    echo "$LAN_IP"
    return
  fi
  if command -v ipconfig >/dev/null 2>&1; then
    for iface in en0 en1; do
      local ip
      ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      if [[ -n "$ip" ]]; then
        echo "$ip"
        return
      fi
    done
  fi
  echo "10.0.0.122"
}

LAN_IP="$(detect_lan_ip)"
export LAN_IP

echo "==> LAN_IP=$LAN_IP (API_BASE_URL for debug build)"
echo "==> ./gradlew :app:assembleDebug"
./gradlew :app:assembleDebug

if [[ ! -f "$APK" ]]; then
  echo "error: APK not found at $APK" >&2
  exit 1
fi

if ! command -v "$ADB" >/dev/null 2>&1; then
  echo "error: adb not found (set ADB=... or install Android platform-tools)" >&2
  exit 1
fi

DEVICES="$("$ADB" devices | awk 'NR>1 && $2=="device" { print $1 }')"
if [[ -z "$DEVICES" ]]; then
  echo "error: no adb device/emulator (run: adb devices)" >&2
  exit 1
fi

echo "==> $ADB install -r $APK"
"$ADB" install -r "$APK"

echo "==> Done. Cloud Store POS debug APK installed."
