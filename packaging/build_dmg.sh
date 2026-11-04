#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames macOS Apple Silicon DMG Builder
# Generates a customized, Apple-grade drag-and-drop installer DMG with custom
# background art, volume icon, Finder layout, and UDZO compression.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_PRODUCTS="${PROJECT_ROOT}/build/DerivedData/Build/Products/Release"
APP_SOURCE="${BUILD_PRODUCTS}/frames.app"
DIST_DIR="${PROJECT_ROOT}/dist"
WEBSITE_DOWNLOADS="${PROJECT_ROOT}/website/public/downloads"
VERSION="${1:-${VERSION:-}}"
if [[ -z "${VERSION}" ]]; then
    # Extract MARKETING_VERSION from project.xcproj
    VERSION=$(grep '"MARKETING_VERSION":' "${PROJECT_ROOT}/frames.xcodeproj/project.xcproj" | head -n 1 | sed -E 's/.*"MARKETING_VERSION": "([^"]+)".*/\1/')
    VERSION="${VERSION:-1.1.0}"
fi
# Strip leading 'v' if passed
VERSION="${VERSION#v}"

TEMP_DMG="/tmp/Frames_rw_staging.dmg"
FINAL_DMG_NAME="Frames-v${VERSION}-AppleSilicon.dmg"
FINAL_DMG="${DIST_DIR}/${FINAL_DMG_NAME}"
VOLUME_NAME="Frames"

echo "==> [1/6] Verifying release build..."
if [[ ! -d "${APP_SOURCE}" ]]; then
    echo "Release app not found at ${APP_SOURCE}. Building now with xcodebuild..."
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
        -project "${PROJECT_ROOT}/frames.xcodeproj" \
        -scheme frames \
        -configuration Release \
        -derivedDataPath "${PROJECT_ROOT}/build/DerivedData" \
        build
fi

echo "==> [2/6] Preparing workspace and background image..."
mkdir -p "${DIST_DIR}" "${WEBSITE_DOWNLOADS}" "${SCRIPT_DIR}"

# Ensure background image is rendered
if [[ ! -f "${SCRIPT_DIR}/dmg-background.png" ]]; then
    echo "Rendering DMG retina background..."
    swift "${SCRIPT_DIR}/build_dmg_background.swift" "${SCRIPT_DIR}/dmg-background.png"
fi

# Clean up any existing temp files or mounted volumes
rm -f "${TEMP_DMG}" "${FINAL_DMG}"
if [[ -d "/Volumes/${VOLUME_NAME}" ]]; then
    echo "Unmounting existing /Volumes/${VOLUME_NAME}..."
    hdiutil detach "/Volumes/${VOLUME_NAME}" -force 2>/dev/null || true
fi

echo "==> [3/6] Creating writable staging disk image..."
# 160MB is plenty for Frames.app (approx 15MB) while giving ample scratch space
hdiutil create -size 160m -fs HFS+ -volname "${VOLUME_NAME}" -ov "${TEMP_DMG}"

echo "==> [4/6] Mounting staging image and populating contents..."
ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}")
DEVICE=$(echo "${ATTACH_OUTPUT}" | grep -E '^/dev/' | head -n 1 | awk '{print $1}')
MOUNT_DIR="/Volumes/${VOLUME_NAME}"

# Trap to guarantee unmount if error occurs
cleanup() {
    if [[ -d "${MOUNT_DIR}" ]]; then
        echo "Detaching ${MOUNT_DIR}..."
        hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null || true
    fi
    rm -f "${TEMP_DMG}"
}
trap cleanup ERR

echo "Mounted at ${MOUNT_DIR} on device ${DEVICE}"

# Copy application bundle
echo "Copying Frames.app..."
cp -R "${APP_SOURCE}" "${MOUNT_DIR}/Frames.app"

# Create /Applications symlink
echo "Creating /Applications symlink..."
ln -s /Applications "${MOUNT_DIR}/Applications"

# Set up hidden background image
mkdir -p "${MOUNT_DIR}/.background"
cp "${SCRIPT_DIR}/dmg-background.png" "${MOUNT_DIR}/.background/background.png"

# Set up Volume Icon
if [[ -f "${PROJECT_ROOT}/frames/AppIcon.icns" ]]; then
    echo "Setting custom Volume Icon..."
    cp "${PROJECT_ROOT}/frames/AppIcon.icns" "${MOUNT_DIR}/.VolumeIcon.icns"
    SetFile -c icnC "${MOUNT_DIR}/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true
fi

echo "==> [5/6] Customizing Finder window layout via AppleScript..."
# Run AppleScript to arrange icons and set window geometry
osascript <<EOF || echo "Finder styling applied with fallback"
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {360, 140, 1020, 540}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "Frames.app" of container window to {175, 205}
        set position of item "Applications" of container window to {485, 205}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Ensure all file operations are flushed
sync
sleep 1

echo "Detaching volume ${MOUNT_DIR}..."
hdiutil detach "${DEVICE}" -force

echo "==> [6/6] Converting into compressed, read-only Apple distribution DMG (UDZO)..."
hdiutil convert "${TEMP_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "${FINAL_DMG}"

# Clean up temp DMG
rm -f "${TEMP_DMG}"
trap - ERR

# Create convenience copies
cp "${FINAL_DMG}" "${DIST_DIR}/Frames.dmg"
cp "${FINAL_DMG}" "${WEBSITE_DOWNLOADS}/Frames-AppleSilicon.dmg"
cp "${FINAL_DMG}" "${WEBSITE_DOWNLOADS}/${FINAL_DMG_NAME}"

DMG_SIZE=$(du -h "${FINAL_DMG}" | awk '{print $1}')
SHA256=$(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')

echo ""
echo "======================================================================"
echo "  FRAMES APPLE SILICON DMG GENERATED SUCCESSFULLY!"
echo "======================================================================"
echo "  Path:   ${FINAL_DMG}"
echo "  Size:   ${DMG_SIZE}"
echo "  SHA256: ${SHA256}"
echo "  Mirror: ${WEBSITE_DOWNLOADS}/Frames-AppleSilicon.dmg"
echo "======================================================================"
