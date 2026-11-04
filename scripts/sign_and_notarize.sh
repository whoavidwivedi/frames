#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames - Official Apple Developer ID Signing & Notarization Pipeline
# ==============================================================================
# Usage:
#   ./scripts/sign_and_notarize.sh \
#       --identity "Developer ID Application: Your Name (TEAM_ID)" \
#       --keychain-profile "FRAMES_NOTARY" \
#       [--dmg path/to/Frames.dmg]
# ==============================================================================

IDENTITY=""
KEYCHAIN_PROFILE=""
DMG_PATH=""

print_usage() {
    cat <<EOF
Usage: $0 --identity "<Developer ID Identity>" --keychain-profile "<Keychain Profile>" [--dmg <path>]

Required Arguments:
  --identity          Developer ID Application certificate identity name
                      (e.g., "Developer ID Application: John Doe (ABC123XYZ)")
  --keychain-profile  Keychain credentials profile created with:
                      xcrun notarytool store-credentials "PROFILE_NAME" \\
                        --apple-id "your@appleid.com" \\
                        --team-id "ABC123XYZ" \\
                        --password "app-specific-password"

Optional Arguments:
  --dmg               Path to the .dmg file to notarize (defaults to dist/Frames.dmg)
  -h, --help          Show this help message

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            IDENTITY="$2"
            shift 2
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [[ -z "${IDENTITY}" || -z "${KEYCHAIN_PROFILE}" ]]; then
    echo "❌ Error: Both --identity and --keychain-profile are required."
    print_usage
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${DMG_PATH:-${PROJECT_ROOT}/dist/Frames.dmg}"

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "⚠️ DMG not found at ${DMG_PATH}. Building fresh DMG first..."
    "${PROJECT_ROOT}/packaging/build_dmg.sh"
fi

echo "======================================================================"
echo "  FRAMES OFFICIAL APPLE SIGNING & NOTARIZATION PIPELINE"
echo "======================================================================"
echo "  DMG Target:       ${DMG_PATH}"
echo "  Signing Identity: ${IDENTITY}"
echo "  Keychain Profile: ${KEYCHAIN_PROFILE}"
echo "======================================================================"

echo "==> [1/4] Signing DMG image container with Developer ID and secure timestamp..."
codesign --force \
    --sign "${IDENTITY}" \
    --timestamp \
    "${DMG_PATH}"

echo "Verifying DMG signature..."
codesign --verify --verbose=2 "${DMG_PATH}"

echo "==> [2/4] Submitting DMG to Apple Notary Service (xcrun notarytool)..."
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

echo "==> [3/4] Stapling official Apple Notarization Ticket to DMG..."
xcrun stapler staple "${DMG_PATH}"

echo "==> [4/4] Validating offline Gatekeeper verification..."
spctl -a -t open --context context:primary-signature -v "${DMG_PATH}"

echo ""
echo "🎉 SUCCESS: Frames DMG has been officially signed, notarized, and stapled!"
echo "   Users on any Apple Silicon Mac can now double-click to install without"
echo "   Gatekeeper security blocks or malicious software warnings."
echo "======================================================================"
