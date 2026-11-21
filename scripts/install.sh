#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames macOS Automated Terminal Installer
# https://github.com/whoavidwivedi/frames
# ==============================================================================
# Installs Frames directly to /Applications after verifying the published
# SHA-256 checksum and the Developer ID code signature, then launches the app.
# ==============================================================================

# Colors & Formatting
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

log_info() {
    echo -e "${BLUE}==>${RESET} ${BOLD}$1${RESET}"
}

log_success() {
    echo -e "${GREEN}✔${RESET} ${BOLD}$1${RESET}"
}

log_warn() {
    echo -e "${YELLOW}⚠️${RESET}  $1"
}

log_error() {
    echo -e "${RED}✖ Error:${RESET} $1" >&2
}

# 1. Platform & Environment Preflight
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
    log_error "Frames is engineered exclusively for macOS. Detected OS: $OS"
    exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
    log_warn "Detected architecture: $ARCH. Frames is fully optimized for Apple Silicon (M1/M2/M3/M4)."
fi

CHANNEL="${CHANNEL:-stable}"
for arg in "$@"; do
    case "$arg" in
        --beta|--canary)
            CHANNEL="beta"
            ;;
        --stable)
            CHANNEL="stable"
            ;;
        --channel=*)
            CHANNEL="${arg#*=}"
            ;;
    esac
done

echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}│                   FRAMES macOS INSTALLER                │${RESET}"
echo -e "${BOLD}│       Native Apple Silicon Video Player & Dashboard     │${RESET}"
echo -e "${BOLD}└─────────────────────────────────────────────────────────┘${RESET}"
echo -e "  Stream: ${BOLD}${CHANNEL}${RESET}"
echo ""

# 2. Query GitHub Releases API for Version
if [[ "${CHANNEL}" == "beta" || "${CHANNEL}" == "canary" ]]; then
    log_info "Fetching latest Frames Beta/Canary release from GitHub..."
    REPO="whoavidwivedi/frames"
    LATEST_JSON=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${REPO}/releases?per_page=5" 2>/dev/null || true)
    if [[ -z "${LATEST_JSON}" ]]; then
        # Fallback to latest endpoint
        LATEST_JSON=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
    fi
else
    log_info "Fetching latest Frames Stable release from GitHub..."
    REPO="whoavidwivedi/frames"
    LATEST_JSON=$(curl -fsSL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
fi

if [[ -z "${LATEST_JSON}" ]]; then
    log_error "Unable to connect to GitHub API. Please check your internet connection."
    exit 1
fi

TAG_NAME=$(echo "${LATEST_JSON}" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
if [[ -z "${TAG_NAME}" ]]; then
    log_error "Could not resolve latest release tag from GitHub."
    exit 1
fi

# Locate the macOS ZIP asset and its SHA-256 manifest. Both are required;
# an asset without a published checksum is never installed.
DOWNLOAD_URL=$(echo "${LATEST_JSON}" | grep -o 'https://[^"]*Frames-[^"]*-macOS\.zip' | head -n 1 || true)
CHECKSUM_URL=$(echo "${LATEST_JSON}" | grep -o 'https://[^"]*SHA256SUMS\.txt' | head -n 1 || true)

if [[ -z "${DOWNLOAD_URL}" || -z "${CHECKSUM_URL}" ]]; then
    log_error "Release ${TAG_NAME} does not publish a macOS ZIP and SHA256SUMS.txt. Refusing to install unverified software."
    exit 1
fi

log_success "Found latest version: ${BOLD}${TAG_NAME}${RESET}"

# 3. Download Asset to Secure Temporary Directory
TMP_DIR=$(mktemp -d -t frames_install_XXXXXX)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARCHIVE_NAME=$(basename "${DOWNLOAD_URL}")
ARCHIVE_FILE="${TMP_DIR}/${ARCHIVE_NAME}"
MANIFEST_FILE="${TMP_DIR}/SHA256SUMS.txt"

log_info "Downloading ${TAG_NAME} package..."
curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${ARCHIVE_FILE}"

log_info "Downloading release checksum manifest..."
curl -fsSL "${CHECKSUM_URL}" -o "${MANIFEST_FILE}"

log_info "Verifying SHA-256 checksum..."
if ! (cd "${TMP_DIR}" && shasum -a 256 -c "${MANIFEST_FILE}"); then
    log_error "Checksum verification failed. The package was not installed."
    exit 1
fi
log_success "Checksum verified."

# 4. Extract Application Bundle
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

APP_BUNDLE=""
if [[ "${ARCHIVE_FILE}" == *.dmg ]]; then
    log_info "Mounting disk image..."
    MOUNT_DIR="${TMP_DIR}/mount"
    mkdir -p "${MOUNT_DIR}"
    hdiutil attach "${ARCHIVE_FILE}" -nobrowse -mountpoint "${MOUNT_DIR}" -quiet
    
    if [[ -d "${MOUNT_DIR}/Frames.app" ]]; then
        cp -R "${MOUNT_DIR}/Frames.app" "${EXTRACT_DIR}/"
        APP_BUNDLE="${EXTRACT_DIR}/Frames.app"
    elif [[ -d "${MOUNT_DIR}/frames.app" ]]; then
        cp -R "${MOUNT_DIR}/frames.app" "${EXTRACT_DIR}/Frames.app"
        APP_BUNDLE="${EXTRACT_DIR}/Frames.app"
    fi
    hdiutil detach "${MOUNT_DIR}" -quiet 2>/dev/null || true
else
    log_info "Extracting application archive..."
    ditto -xk "${ARCHIVE_FILE}" "${EXTRACT_DIR}"
    if [[ -d "${EXTRACT_DIR}/Frames.app" ]]; then
        APP_BUNDLE="${EXTRACT_DIR}/Frames.app"
    elif [[ -d "${EXTRACT_DIR}/frames.app" ]]; then
        mv "${EXTRACT_DIR}/frames.app" "${EXTRACT_DIR}/Frames.app"
        APP_BUNDLE="${EXTRACT_DIR}/Frames.app"
    fi
fi

if [[ -z "${APP_BUNDLE}" || ! -d "${APP_BUNDLE}" ]]; then
    log_error "Expected Frames.app bundle not found inside downloaded package."
    exit 1
fi

log_info "Verifying Developer ID code signature..."
if ! codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}" >/dev/null 2>&1; then
    log_error "Downloaded application has an invalid code signature. Installation aborted."
    exit 1
fi
if ! codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
    log_error "Downloaded application is not Developer ID signed. Installation aborted."
    exit 1
fi
log_success "Developer ID signature verified."

# 5. Install to /Applications
DEST_APP="/Applications/Frames.app"
log_info "Installing Frames to ${DEST_APP}..."

# If currently running, gently quit old process
if pgrep -x "frames" >/dev/null 2>&1 || pgrep -x "Frames" >/dev/null 2>&1; then
    log_warn "Frames is currently running. Closing running instance for upgrade..."
    pkill -x "frames" 2>/dev/null || true
    pkill -x "Frames" 2>/dev/null || true
    sleep 0.5
fi

# Remove existing installation
if [[ -d "${DEST_APP}" ]]; then
    rm -rf "${DEST_APP}"
fi
cp -R "${APP_BUNDLE}" "${DEST_APP}"

# 6. Post-install verification
log_info "Verifying installed application..."
if ! codesign --verify --deep --strict --verbose=2 "${DEST_APP}" >/dev/null 2>&1; then
    log_error "Installed application failed signature verification."
    exit 1
fi
log_success "Installation verified: package checksum and Developer ID signature both valid."

# 7. Launch Application
echo ""
log_success "🎉 Frames ${TAG_NAME} has been successfully installed to /Applications!"
echo ""
log_info "Launching Frames..."
open -a "${DEST_APP}"

echo -e "${GREEN}Enjoy smooth hardware-accelerated playback on Apple Silicon!${RESET}\n"
