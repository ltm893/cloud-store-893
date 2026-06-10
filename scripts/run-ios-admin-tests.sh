#!/usr/bin/env bash
# run-ios-admin-tests.sh — sync portrait scripts, Node checks, then XCTest (macOS + Xcode).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios-admin"

cd "$PROJECT_ROOT"

echo "== Sync iOS portrait script resources =="
node scripts/sync-ios-portrait-resources.js

echo "== Node: admin orientation + iOS portrait scripts =="
node --test test/admin-orientation.test.js test/ios-admin-portrait.test.js

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping XCTest (requires macOS + Xcode)."
  exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Skipping XCTest (xcodebuild not found)."
  exit 0
fi

echo "== XCTest: CloudStoreAdminTests =="
cd "$IOS_DIR"
SIM_ID="$(xcrun simctl list devices available 2>/dev/null | awk -F'[()]' '/iPhone 16 \(/ {print $2; exit}')"
if [[ -z "$SIM_ID" ]]; then
  echo "No iPhone 16 simulator found; skipping XCTest." >&2
  exit 0
fi
xcodebuild test \
  -project CloudStoreAdmin.xcodeproj \
  -scheme CloudStoreAdmin \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -only-testing:CloudStoreAdminTests \
  CODE_SIGNING_ALLOWED=NO

echo "iOS admin tests passed."
