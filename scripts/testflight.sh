#!/bin/bash
# testflight.sh — archive, export, and upload BookScan to TestFlight.
#
# PREREQUISITES (one-time setup):
#   1. Create an App Store Connect API key:
#      App Store Connect → Users and Access → Integrations → App Store Connect API
#      Role: Developer or App Manager. Download the .p8 file once (it can't be re-downloaded).
#
#   2. Install the key where Xcode/altool expects it:
#      mkdir -p ~/.appstoreconnect/private_keys
#      cp ~/Downloads/AuthKey_XXXXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
#
#   3. Fill in the three variables below from the API key page.
#
#   4. Create the app record in App Store Connect (if you haven't already):
#      Apps → "+" → New App
#      Bundle ID: memeka.BookScan
#      SKU: BookScan (or anything unique)
#
# USAGE:
#   chmod +x scripts/testflight.sh
#   ./scripts/testflight.sh

set -euo pipefail

# ── Configure these from App Store Connect → Users and Access → Keys ─────────
ASC_KEY_ID=""        # e.g. "ABCDE12345"
ASC_ISSUER_ID=""     # e.g. "12345678-1234-1234-1234-123456789012"
ASC_KEY_PATH=""      # e.g. "$HOME/.appstoreconnect/private_keys/AuthKey_ABCDE12345.p8"
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="BookScan"
CONFIGURATION="Release"
ARCHIVE_PATH="$PROJECT_DIR/build/BookScan.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/BookScanExport"

# ── Validate prerequisites ────────────────────────────────────────────────────
if [[ -z "$ASC_KEY_ID" || -z "$ASC_ISSUER_ID" || -z "$ASC_KEY_PATH" ]]; then
    echo "❌  Fill in ASC_KEY_ID, ASC_ISSUER_ID, and ASC_KEY_PATH at the top of this script."
    exit 1
fi

if [[ ! -f "$ASC_KEY_PATH" ]]; then
    echo "❌  API key not found at: $ASC_KEY_PATH"
    echo "    Download it from App Store Connect and copy it there."
    exit 1
fi

echo "▶  Project: $PROJECT_DIR"
echo "▶  Scheme:  $SCHEME ($CONFIGURATION)"
echo ""

# ── Step 1: Archive ────────────────────────────────────────────────────────────
echo "📦  Archiving…"
xcodebuild archive \
    -project "$PROJECT_DIR/BookScan.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    -allowProvisioningUpdates \
    -destination "generic/platform=iOS" \
    | xcpretty 2>/dev/null || cat  # xcpretty is optional; falls back to raw output
echo "✅  Archive: $ARCHIVE_PATH"
echo ""

# ── Step 2: Export + upload to App Store Connect ──────────────────────────────
echo "🚀  Exporting and uploading to TestFlight…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    -allowProvisioningUpdates
echo ""
echo "✅  Upload complete."
echo "    Check App Store Connect → TestFlight — the build appears there"
echo "    within a few minutes (processing takes ~10–20 min before it's"
echo "    distributable to testers)."
