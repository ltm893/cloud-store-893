#!/usr/bin/env bash
# run-ios-pos-tests.sh — XCTest for CloudStorePos (macOS + Xcode).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios-pos"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping XCTest (requires macOS + Xcode)."
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Skipping XCTest (xcodebuild not found)."
  exit 0
fi

echo "== XCTest: CloudStorePosTests =="
cd "$IOS_DIR"
SIM_ID="$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPad \(A16\)' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
if [[ -z "$SIM_ID" ]]; then
  echo "No iPad simulator found; skipping XCTest." >&2
  exit 0
fi
xcodebuild test \
  -project CloudStorePos.xcodeproj \
  -scheme CloudStorePos \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:CloudStorePosTests \
  CODE_SIGNING_ALLOWED=NO

echo "iOS POS tests passed."
