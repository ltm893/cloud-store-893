#!/usr/bin/env bash
# run-lister-tests.sh — Node unit tests + XCTest (macOS + Xcode).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios-lister"

cd "$PROJECT_ROOT"

echo "== Node: inventory lookup =="
node --test test/inventory-lookup.test.js

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping XCTest (requires macOS + Xcode)."
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Skipping XCTest (xcodebuild not found)."
  exit 0
fi

echo "== XCTest: CloudStoreListerTests =="
cd "$IOS_DIR"
SIM_ID="$(xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPhone 16 \(/ {print $2; exit}')"
if [[ -z "$SIM_ID" ]]; then
  echo "No iPhone 16 simulator found; skipping XCTest." >&2
  exit 0
fi
xcodebuild test \
  -project CloudStoreLister.xcodeproj \
  -scheme CloudStoreLister \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:CloudStoreListerTests \
  CODE_SIGNING_ALLOWED=NO

echo "iOS lister tests passed."
