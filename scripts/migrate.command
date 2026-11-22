#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames macOS One-Time Migration Installer
# https://github.com/whoavidwivedi/frames
# ==============================================================================
# This script exists for one specific reason: Frames v1.9.4 and v1.9.5 embed an
# updater that only accepts Apple-issued Developer ID signatures. An ad-hoc
# build can never satisfy that check, so those versions cannot self-upgrade and
# fail with OSStatus -67050. This script performs the one-time replacement with
# a checksum-verified, locally signed build. After it runs, the in-app updater
# in the new build handles all future unsigned OTA updates with a warning.
#
# This is intentionally NOT scripts/install.sh. The one-line installer remains
# strict and continues to refuse unsigned/ad-hoc builds.
# ==============================================================================

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

usage() {
    cat <<'USAGE'
Frames one-time migration installer

Usage:
  ./migrate.command              Replace an older Frames with the latest verified release
  ./migrate.command --dry-run    Download and verify only; do not replace the installed app
  ./migrate.command --help       Show this help

Double-clicking this file in Finder does the same thing as running it with no
arguments: it downloads the latest Frames release, verifies its SHA-256
checksum and bundle identity, then replaces your installed copy once.

After this migration, future in-app updates work normally.

Developer ID-signed releases additionally require FRAMES_EXPECTED_TEAM_ID to be
set to the publisher's 10-character Apple team ID so the signing identity is
pinned. Unsigned/ad-hoc releases do not need it.
USAGE
}

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        *)
            log_error "Unknown argument: $arg"
            usage
            exit 2
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 1. Preflight
# ------------------------------------------------------------------------------
OS="$(uname -s)"
if [[ "$OS" != "Darwin" ]]; then
    log_error "Frames is engineered exclusively for macOS. Detected OS: $OS"
    exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
    log_warn "Detected architecture: $ARCH. Frames is optimized for Apple Silicon (M-series)."
fi

echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}│            FRAMES ONE-TIME MIGRATION INSTALLER          │${RESET}"
echo -e "${BOLD}│   Fixes OSStatus -67050 from older in-app updaters      │${RESET}"
echo -e "${BOLD}└─────────────────────────────────────────────────────────┘${RESET}"
echo ""
log_warn "This replaces your current Frames installation with the latest verified release."
log_warn "Unsigned builds are ad-hoc signed and are not notarized. Your data and library are untouched."
echo ""

# ------------------------------------------------------------------------------
# 2. Resolve the latest release from GitHub
# ------------------------------------------------------------------------------
REPO="whoavidwivedi/frames"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

log_info "Fetching latest Frames release..."
LATEST_JSON=$(curl -fsSL --proto '=https' --proto-redir '=https' \
    -H "Accept: application/vnd.github.v3+json" \
    -H "User-Agent: Frames-Migration/1.0" \
    "$API_URL" 2>/dev/null || true)

if [[ -z "$LATEST_JSON" ]]; then
    log_error "Unable to reach GitHub. Check your internet connection and try again."
    exit 1
fi

TAG_NAME=$(echo "$LATEST_JSON" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)
DOWNLOAD_URL=$(echo "$LATEST_JSON" | grep -o 'https://[^"]*Frames-[^"]*-macOS\.zip' | head -n 1 || true)
CHECKSUM_URL=$(echo "$LATEST_JSON" | grep -o 'https://[^"]*SHA256SUMS\.txt' | head -n 1 || true)

if [[ -z "$TAG_NAME" || -z "$DOWNLOAD_URL" || -z "$CHECKSUM_URL" ]]; then
    log_error "Latest release does not publish a macOS ZIP and SHA256SUMS.txt. Nothing was changed."
    exit 1
fi

# Never follow a redirect to a non-HTTPS host, even if the API response is tampered with.
if [[ "$DOWNLOAD_URL" != https://* || "$CHECKSUM_URL" != https://* ]]; then
    log_error "Release download URLs are not HTTPS. Nothing was changed."
    exit 1
fi

log_success "Latest release: ${BOLD}${TAG_NAME}${RESET}"

# ------------------------------------------------------------------------------
# 3. Download and checksum-verify the archive
# ------------------------------------------------------------------------------
TMP_DIR=$(mktemp -d -t frames_migration_XXXXXX)
BACKUP_DIR=""
RESTORE_ON_FAILURE=0
DEST_APP=""
cleanup() {
    local status=$?
    if [[ "$RESTORE_ON_FAILURE" -eq 1 && -d "${BACKUP_DIR}/Frames.app" ]]; then
        rm -rf "$DEST_APP" 2>/dev/null || true
        cp -R "${BACKUP_DIR}/Frames.app" "$DEST_APP" 2>/dev/null || true
        echo "Original Frames installation was restored." >&2
    fi
    if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
        rm -rf "$BACKUP_DIR" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT

# Keep the published archive name: SHA256SUMS.txt is checked relative to it.
ARCHIVE_FILE="${TMP_DIR}/$(basename "$DOWNLOAD_URL")"
MANIFEST_FILE="${TMP_DIR}/SHA256SUMS.txt"
EXTRACT_DIR="${TMP_DIR}/extracted"

log_info "Downloading ${TAG_NAME}..."
curl -fL --proto '=https' --proto-redir '=https' --progress-bar "$DOWNLOAD_URL" -o "$ARCHIVE_FILE"

log_info "Downloading checksum manifest..."
curl -fsSL --proto '=https' --proto-redir '=https' "$CHECKSUM_URL" -o "$MANIFEST_FILE"

log_info "Verifying SHA-256 checksum..."
if ! (cd "$TMP_DIR" && shasum -a 256 -c "$MANIFEST_FILE"); then
    log_error "Checksum verification failed. Nothing was changed."
    exit 1
fi
log_success "Checksum verified."

# ------------------------------------------------------------------------------
# 4. Extract and verify the bundle before touching the installation
# ------------------------------------------------------------------------------
mkdir -p "$EXTRACT_DIR"
log_info "Extracting application bundle..."
ditto -xk "$ARCHIVE_FILE" "$EXTRACT_DIR"

APP_BUNDLE=""
if [[ -d "${EXTRACT_DIR}/Frames.app" ]]; then
    APP_BUNDLE="${EXTRACT_DIR}/Frames.app"
elif [[ -d "${EXTRACT_DIR}/frames.app" ]]; then
    APP_BUNDLE="${EXTRACT_DIR}/frames.app"
else
    log_error "Expected Frames.app was not found inside the downloaded archive. Nothing was changed."
    exit 1
fi

verify_bundle() {
    local bundle="$1"
    [[ -d "$bundle" ]] || return 1
    [[ -f "$bundle/Contents/Info.plist" ]] || return 1
    [[ -d "$bundle/Contents/MacOS" ]] || return 1

    local bundle_id
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$bundle/Contents/Info.plist" 2>/dev/null || true)
    [[ "$bundle_id" == "whoavidwivedi.frames" ]] || return 1

    codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 || return 1

    local signature_info
    signature_info=$(codesign -dvvv "$bundle" 2>&1 || true)
    if grep -q 'Signature=adhoc' <<<"$signature_info"; then
        return 0
    fi
    if grep -q 'Authority=Developer ID Application:' <<<"$signature_info"; then
        # A Developer ID bundle must satisfy the same Apple-anchored, team-pinned
        # requirement the in-app updater enforces. The team must come from a
        # trusted local source (the caller), never from the downloaded bundle.
        local expected_team="${FRAMES_EXPECTED_TEAM_ID:-}"
        expected_team="$(echo "$expected_team" | tr -d '[:space:]')"
        if [[ ${#expected_team} -ne 10 || ! "$expected_team" =~ ^[A-Za-z0-9]+$ ]]; then
            return 1
        fi
        local requirement
        requirement="anchor apple generic and identifier \"whoavidwivedi.frames\" "
        requirement+="and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
        requirement+="and certificate leaf[field.1.2.840.113635.100.6.1.13] exists "
        requirement+="and certificate leaf[subject.OU] = \"${expected_team}\""
        codesign -v -R="$requirement" "$bundle" >/dev/null 2>&1 || return 1
        return 0
    fi
    return 1
}

log_info "Verifying bundle identity and signature..."
if ! verify_bundle "$APP_BUNDLE"; then
    if codesign -dvvv "$APP_BUNDLE" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
        log_error "Developer ID releases require FRAMES_EXPECTED_TEAM_ID to be set to the publisher's 10-character team ID."
    fi
    log_error "Downloaded bundle failed identity/signature verification. Nothing was changed."
    exit 1
fi
log_success "Bundle identity and signature verified."

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo ""
    log_success "Dry run complete: ${TAG_NAME} downloaded and verified. No files were changed."
    exit 0
fi

# ------------------------------------------------------------------------------
# 5. Replace the installed copy, with a rollback on failure
# ------------------------------------------------------------------------------
for candidate in "/Applications/Frames.app" "$HOME/Applications/Frames.app"; do
    if [[ -d "$candidate" ]]; then
        DEST_APP="$candidate"
        break
    fi
done
if [[ -z "$DEST_APP" ]]; then
    DEST_APP="/Applications/Frames.app"
fi

DEST_PARENT="$(dirname "$DEST_APP")"
if [[ ! -d "$DEST_PARENT" ]]; then
    mkdir -p "$DEST_PARENT" 2>/dev/null || true
fi
if [[ ! -w "$DEST_PARENT" ]]; then
    log_error "Cannot write to ${DEST_PARENT}. Run this script as a user who can install applications there. Nothing was changed."
    exit 1
fi

if pgrep -x frames >/dev/null 2>&1 || pgrep -x Frames >/dev/null 2>&1; then
    log_warn "Frames is running. Closing it before replacement..."
    pkill -x frames 2>/dev/null || true
    pkill -x Frames 2>/dev/null || true
    sleep 1
fi

BACKUP_DIR=$(mktemp -d -t frames_migration_backup_XXXXXX)
if [[ -d "$DEST_APP" ]]; then
    log_info "Backing up existing installation..."
    cp -R "$DEST_APP" "${BACKUP_DIR}/Frames.app"
    RESTORE_ON_FAILURE=1
fi

log_info "Installing ${TAG_NAME} to ${DEST_APP}..."
rm -rf "$DEST_APP"
cp -R "$APP_BUNDLE" "$DEST_APP"

if ! verify_bundle "$DEST_APP"; then
    log_error "Installed bundle failed verification. Migration aborted."
    exit 1
fi
RESTORE_ON_FAILURE=0

# Gatekeeper quarantine is expected on a downloaded archive; clear it so the
# ad-hoc build can launch. This does not and cannot create a Developer ID.
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

log_success "Installed and verified Frames ${TAG_NAME}."

# ------------------------------------------------------------------------------
# 6. Launch
# ------------------------------------------------------------------------------
echo ""
log_success "Migration complete. Future in-app updates will work without this error."
log_info "Launching Frames..."
open -a "$DEST_APP"

echo -e "${GREEN}You're now on Frames ${TAG_NAME}. Enjoy!${RESET}\n"
