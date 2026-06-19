#!/usr/bin/env bash
# scripts/ios/testflight-upload.sh
#
# Archive and upload ios-admin and/or ios-pos to App Store Connect (TestFlight).
#
# USAGE
#   ./scripts/ios/testflight-upload.sh [admin|pos|both]   (default: both)
#
# PREREQUISITES
#   - Xcode 16+ command-line tools installed
#   - Apple Developer account signed in (Xcode → Settings → Accounts), OR
#     set ASC_API_KEY_PATH / ASC_API_KEY_ID / ASC_API_ISSUER_ID for keyless CI upload.
#   - App IDs registered in developer.apple.com:
#       com.cloudstore.admin
#       com.cloudstore.pos
#   - Apps created in App Store Connect (appstoreconnect.apple.com):
#       Cloud Store Admin  →  bundle ID com.cloudstore.admin
#       Cloud Store POS    →  bundle ID com.cloudstore.pos
#
# BUILD NUMBER
#   Set BUILD_NUMBER env var to override (default: 1). Each upload to ASC must have
#   a build number strictly greater than the last accepted build for that version.
#   Example: BUILD_NUMBER=2 ./scripts/ios/testflight-upload.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="${1:-both}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHIVES_DIR="$REPO_ROOT/build/archives"
EXPORT_DIR="$REPO_ROOT/build/export"

mkdir -p "$ARCHIVES_DIR" "$EXPORT_DIR"

# ── Optional: App Store Connect API key (for CI / no-keychain upload) ─────────
# Set these env vars if you are NOT using a Xcode-signed-in account:
#   ASC_API_KEY_PATH   path to the .p8 key file downloaded from App Store Connect
#   ASC_API_KEY_ID     the key ID (e.g. ABC1234567)
#   ASC_API_ISSUER_ID  the issuer UUID from App Store Connect → Users → Keys
ALTOOL_AUTH_FLAGS=()
if [[ -n "${ASC_API_KEY_PATH:-}" ]]; then
    ALTOOL_AUTH_FLAGS+=(
        --apiKey    "$ASC_API_KEY_ID"
        --apiIssuer "$ASC_API_ISSUER_ID"
    )
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

bump_build_number() {
    local proj="$1"
    agvtool new-version -all "$BUILD_NUMBER" 2>/dev/null || \
        xcrun agvtool new-version -all "$BUILD_NUMBER"
    echo "  → build number set to $BUILD_NUMBER"
}

archive_app() {
    local name="$1"       # CloudStoreAdmin | CloudStorePos
    local proj_dir="$2"   # absolute path to the .xcodeproj parent
    local scheme="$3"
    local archive_path="$ARCHIVES_DIR/${name}.xcarchive"

    echo ""
    echo "▶  Archiving $name (Release, build $BUILD_NUMBER)…"
    (
        cd "$proj_dir"
        bump_build_number "$proj_dir"
        xcodebuild archive \
            -project "${name}.xcodeproj" \
            -scheme   "$scheme" \
            -configuration Release \
            -archivePath "$archive_path" \
            CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
            -allowProvisioningUpdates \
            | xcpretty 2>/dev/null || cat
    )
    echo "  ✓ Archive: $archive_path"
}

upload_app() {
    local name="$1"
    local proj_dir="$2"
    local archive_path="$ARCHIVES_DIR/${name}.xcarchive"
    local export_path="$EXPORT_DIR/${name}"

    echo ""
    echo "▶  Exporting + uploading $name to App Store Connect…"
    xcodebuild -exportArchive \
        -archivePath   "$archive_path" \
        -exportPath    "$export_path" \
        -exportOptionsPlist "$proj_dir/ExportOptions.plist" \
        -allowProvisioningUpdates \
        | xcpretty 2>/dev/null || cat

    # destination=upload in ExportOptions sends directly to ASC.
    # If you switched to destination=export, upload the .ipa manually:
    #   xcrun altool --upload-app -f "$export_path/${name}.ipa" -t ios "${ALTOOL_AUTH_FLAGS[@]}"
    echo "  ✓ Upload complete for $name — check App Store Connect > TestFlight."
}

run_app() {
    local name="$1"
    local proj_dir="$2"
    local scheme="$3"
    archive_app "$name" "$proj_dir" "$scheme"
    upload_app  "$name" "$proj_dir"
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "$TARGET" in
    admin)
        run_app "CloudStoreAdmin" "$REPO_ROOT/ios-admin" "CloudStoreAdmin"
        ;;
    pos)
        run_app "CloudStorePos" "$REPO_ROOT/ios-pos" "CloudStorePos"
        ;;
    both)
        run_app "CloudStoreAdmin" "$REPO_ROOT/ios-admin" "CloudStoreAdmin"
        run_app "CloudStorePos"   "$REPO_ROOT/ios-pos"   "CloudStorePos"
        ;;
    *)
        echo "Usage: $0 [admin|pos|both]"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Done. Next steps in App Store Connect:"
echo "   1. appstoreconnect.apple.com → Your App → TestFlight"
echo "   2. Wait for build processing (usually 5–15 min)"
echo "   3. Add testers: Internal (your team) or External (invite by email)"
echo "   4. External testers need a brief TestFlight review (~24–48 h)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
