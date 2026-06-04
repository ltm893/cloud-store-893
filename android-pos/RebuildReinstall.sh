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

# Android Gradle Plugin does not support running Gradle on JDK 26 yet (jlink / androidJdkImage fails).
# Prefer 21, then 17, when JAVA_HOME is unset.
if [[ -z "${JAVA_HOME:-}" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  for ver in 21 17; do
    jhome="$(/usr/libexec/java_home -v "$ver" 2>/dev/null || true)"
    if [[ -n "$jhome" ]]; then
      export JAVA_HOME="$jhome"
      break
    fi
  done
fi
if [[ -n "${JAVA_HOME:-}" ]]; then
  echo "==> JAVA_HOME=$JAVA_HOME"
else
  echo "warning: set JAVA_HOME to JDK 21 or 17 (Temurin). JDK 26 breaks :app:compileDebugJavaWithJavac." >&2
fi

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

# adb uses TAB between serial and state; wireless serials can contain spaces.
ADB_SERIAL="${ADB_SERIAL:-}"
DEVICE_COUNT=0
while IFS= read -r serial; do
  [[ -z "$serial" ]] && continue
  DEVICE_COUNT=$((DEVICE_COUNT + 1))
  [[ -z "$ADB_SERIAL" ]] && ADB_SERIAL="$serial"
done < <("$ADB" devices | awk -F'\t' 'NR>1 && $2=="device" { print $1 }')

if [[ "$DEVICE_COUNT" -eq 0 ]]; then
  echo "error: no adb device/emulator (run: adb devices)" >&2
  exit 1
fi
if [[ "$DEVICE_COUNT" -gt 1 ]]; then
  echo "==> Multiple devices; using ADB_SERIAL=$ADB_SERIAL (set ADB_SERIAL to override)"
fi

echo "==> $ADB -s \"$ADB_SERIAL\" install -r $APK"
"$ADB" -s "$ADB_SERIAL" install -r "$APK"

echo "==> Done. Cloud Store POS debug APK installed."
