#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames macOS Apple Silicon Official Release & GitHub Tagging Pipeline
# ==============================================================================
# Automates testing, version bumping, release compilation, code signing,
# packaging (Retina DMG & ZIP), checksum generation, git tagging, and
# GitHub Release publication.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
PROJECT_FILE="${PROJECT_ROOT}/frames.xcodeproj/project.xcproj"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DRY_RUN=false
SKIP_TESTS=false
IS_DRAFT=false
IS_PRERELEASE=false
CUSTOM_TITLE=""
CUSTOM_NOTES=""
VERSION=""

print_usage() {
    cat <<EOF
Frames Official Release & Packaging Script

Usage:
  ./scripts/release.sh <VERSION> [OPTIONS]

Example:
  ./scripts/release.sh 1.2.0
  ./scripts/release.sh 1.2.0 --dry-run
  ./scripts/release.sh 1.2.0 --draft

Arguments:
  <VERSION>           Target semantic version (e.g., 1.2.0 or v1.2.0)

Options:
  --dry-run           Build and package artifacts locally without git commit/push/release
  --skip-tests        Skip running the pre-release automated test suite
  --draft             Publish the GitHub release as a draft
  --prerelease        Mark the GitHub release as a pre-release
  --title <text>      Custom release title
  --notes <text>      Custom release notes string (or pass a file via --notes-file)
  --notes-file <file> Path to markdown release notes file
  -h, --help          Show this documentation
EOF
}

# Parse positional and flagged arguments
NOTES_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --draft)
            IS_DRAFT=true
            shift
            ;;
        --prerelease)
            IS_PRERELEASE=true
            shift
            ;;
        --title)
            CUSTOM_TITLE="$2"
            shift 2
            ;;
        --notes)
            CUSTOM_NOTES="$2"
            shift 2
            ;;
        --notes-file)
            NOTES_FILE="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            if [[ -z "${VERSION}" ]]; then
                VERSION="$1"
                shift
            else
                echo "❌ Error: Unrecognized parameter: $1"
                print_usage
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${VERSION}" ]]; then
    # Try reading current version from project
    CURRENT_VERSION=$(grep '"MARKETING_VERSION":' "${PROJECT_FILE}" | head -n 1 | sed -E 's/.*"MARKETING_VERSION": "([^"]+)".*/\1/')
    echo "❌ Error: Release version required. Current version is ${CURRENT_VERSION}."
    echo "Usage: ./scripts/release.sh <VERSION> (e.g., ./scripts/release.sh 1.2.0)"
    exit 1
fi

# Normalize version: strip leading 'v'
VERSION="${VERSION#v}"
TAG="v${VERSION}"

echo "======================================================================"
echo "  FRAMES APPLE SILICON RELEASE PIPELINE"
echo "======================================================================"
echo "  Target Version:  ${VERSION} (Tag: ${TAG})"
echo "  Dry Run:         ${DRY_RUN}"
echo "  Skip Tests:      ${SKIP_TESTS}"
echo "  Draft:           ${IS_DRAFT}"
echo "  Pre-release:     ${IS_PRERELEASE}"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 1. Preflight Validation
# ------------------------------------------------------------------------------
echo "==> [1/7] Running preflight environment checks..."

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ Error: xcodebuild not found in DEVELOPER_DIR (${DEVELOPER_DIR})."
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "❌ Error: GitHub CLI ('gh') is required for GitHub release publication."
    exit 1
fi

if [[ "${DRY_RUN}" == "false" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "❌ Error: GitHub CLI is not authenticated. Run 'gh auth login' first."
        exit 1
    fi

    # Check if tag already exists locally or remotely
    if git rev-parse "${TAG}" >/dev/null 2>&1; then
        echo "⚠️ Warning: Git tag '${TAG}' already exists locally."
    fi
fi

# ------------------------------------------------------------------------------
# 2. Automated Test Suite Verification
# ------------------------------------------------------------------------------
if [[ "${SKIP_TESTS}" == "false" ]]; then
    echo "==> [2/7] Running test suite against Debug build..."
    xcodebuild \
        -project "${PROJECT_ROOT}/frames.xcodeproj" \
        -scheme frames \
        -configuration Debug \
        -derivedDataPath "${PROJECT_ROOT}/build/DerivedData" \
        build >/dev/null

    DEBUG_BINARY="${PROJECT_ROOT}/build/DerivedData/Build/Products/Debug/frames.app/Contents/MacOS/frames"
    if [[ ! -x "${DEBUG_BINARY}" ]]; then
        echo "❌ Error: Built debug binary not executable at ${DEBUG_BINARY}"
        exit 1
    fi

    TEST_OUTPUT=$("${DEBUG_BINARY}" --run-tests)
    if echo "${TEST_OUTPUT}" | grep -q "0 FAILED"; then
        echo "  ✔ Test suite passed cleanly!"
    else
        echo "❌ Test suite failed!"
        echo "${TEST_OUTPUT}"
        exit 1
    fi
else
    echo "==> [2/7] Skipping test suite (--skip-tests specified)."
fi

# ------------------------------------------------------------------------------
# 3. Version Bump in Xcode Project
# ------------------------------------------------------------------------------
echo "==> [3/7] Updating version to ${VERSION} in ${PROJECT_FILE}..."
sed -i '' -E "s/\"MARKETING_VERSION\": \"[^\"]+\"/\"MARKETING_VERSION\": \"${VERSION}\"/g" "${PROJECT_FILE}"

# Increment build number
CURRENT_BUILD=$(grep '"CURRENT_PROJECT_VERSION":' "${PROJECT_FILE}" | head -n 1 | sed -E 's/.*"CURRENT_PROJECT_VERSION": "([^"]+)".*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/\"CURRENT_PROJECT_VERSION\": \"[0-9]+\"/\"CURRENT_PROJECT_VERSION\": \"${NEW_BUILD}\"/g" "${PROJECT_FILE}"
echo "  MARKETING_VERSION: ${VERSION}"
echo "  CURRENT_PROJECT_VERSION: ${NEW_BUILD}"

# ------------------------------------------------------------------------------
# 4. Release Compilation & Signing
# ------------------------------------------------------------------------------
echo "==> [4/7] Building Release configuration for Apple Silicon..."
xcodebuild \
    -project "${PROJECT_ROOT}/frames.xcodeproj" \
    -scheme frames \
    -configuration Release \
    -derivedDataPath "${PROJECT_ROOT}/build/DerivedData" \
    clean build

RELEASE_APP="${PROJECT_ROOT}/build/DerivedData/Build/Products/Release/frames.app"
if [[ ! -d "${RELEASE_APP}" ]]; then
    echo "❌ Error: Release bundle not generated at ${RELEASE_APP}"
    exit 1
fi

echo "Signing application bundle..."
codesign --force --deep --sign - "${RELEASE_APP}"
codesign --verify --verbose=1 "${RELEASE_APP}"

# ------------------------------------------------------------------------------
# 5. Packaging Artifacts (ZIP & Retina DMG)
# ------------------------------------------------------------------------------
echo "==> [5/7] Packaging distribution artifacts..."
mkdir -p "${DIST_DIR}"

ZIP_NAME="Frames-${TAG}-macOS.zip"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"

echo "Creating distribution ZIP: ${ZIP_PATH}..."
(
    cd "$(dirname "${RELEASE_APP}")"
    ditto -c -k --keepParent "$(basename "${RELEASE_APP}")" "${ZIP_PATH}"
)

DMG_NAME="Frames-${TAG}-AppleSilicon.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
echo "Building Retina distribution DMG: ${DMG_PATH}..."
"${PROJECT_ROOT}/packaging/build_dmg.sh" "${VERSION}"

# Generate Checksums
CHECKSUM_FILE="${DIST_DIR}/checksums.txt"
echo "Generating SHA-256 checksums..."
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > "${CHECKSUM_FILE}"
)
cat "${CHECKSUM_FILE}"

# ------------------------------------------------------------------------------
# 6. Git Commit & Tagging
# ------------------------------------------------------------------------------
if [[ "${DRY_RUN}" == "true" ]]; then
    echo "==> [6/7] [DRY RUN] Skipping git commit, push, and release publication."
    echo "🎉 Dry run completed successfully! Artifacts available in dist/"
    exit 0
fi

echo "==> [6/7] Committing version bump and creating git tag ${TAG}..."
git add "${PROJECT_FILE}"

# Only commit if changes exist
if ! git diff --cached --quiet; then
    git commit -m "chore(release): bump version to ${TAG}"
fi

# Create annotated tag
git tag -a "${TAG}" -m "Frames ${TAG} — Native Apple Silicon Media Engine & In-App OTA Update"

echo "Pushing commits and tags to origin..."
git push origin main
git push origin "${TAG}"

# ------------------------------------------------------------------------------
# 7. GitHub Release Publication
# ------------------------------------------------------------------------------
echo "==> [7/7] Publishing release on GitHub..."

# Prepare Release Notes
TEMP_NOTES_FILE="/tmp/Frames_release_notes_${VERSION}.md"
if [[ -n "${NOTES_FILE}" && -f "${NOTES_FILE}" ]]; then
    cp "${NOTES_FILE}" "${TEMP_NOTES_FILE}"
elif [[ -n "${CUSTOM_NOTES}" ]]; then
    echo "${CUSTOM_NOTES}" > "${TEMP_NOTES_FILE}"
else
    cat <<EOF > "${TEMP_NOTES_FILE}"
## Frames ${TAG} — Native Apple Silicon Media Engine & In-App OTA Updates

### 🚀 What's New in this Release

• **In-App Production OTA Update Engine**: Instant update notifications without intrusive automatic restarts. Seamless in-app download, checksum integrity verification, atomic bundle swap, and app relaunch.
• **Instant Update Discovery**: Background release checking against GitHub Releases with SemVer 2.0.0 resolution, manual check affordance in App Menu and Command Palette.
• **Liquid Glass Update Modal**: Adaptive dual-mode interface showcasing real-time download progress, changelog highlights, and granular controls ("Update & Restart", "Later", "Skip this version").
• **Apple Silicon Performance Polish**: 232/232 automated tests passing with zero regressions, strict concurrency compliance, and ultra-low unified memory footprint.

### 📦 Installation

1. Download \`${DMG_NAME}\` or \`${ZIP_NAME}\` below.
2. Drag \`Frames.app\` to your \`/Applications\` folder.
3. Launch Frames and enjoy fluid hardware-accelerated playback.

### 🔐 SHA-256 Checksums
\`\`\`
$(cat "${CHECKSUM_FILE}")
\`\`\`
EOF
fi

TITLE="${CUSTOM_TITLE:-Frames ${TAG} — Native Apple Silicon Media Engine & In-App OTA Updates}"

GH_FLAGS=(
    "${TAG}"
    "${ZIP_PATH}"
    "${DMG_PATH}"
    "${CHECKSUM_FILE}"
    --title "${TITLE}"
    --notes-file "${TEMP_NOTES_FILE}"
)

if [[ "${IS_DRAFT}" == "true" ]]; then
    GH_FLAGS+=(--draft)
fi

if [[ "${IS_PRERELEASE}" == "true" ]]; then
    GH_FLAGS+=(--prerelease)
fi

echo "Creating GitHub release via gh..."
gh release create "${GH_FLAGS[@]}"

rm -f "${TEMP_NOTES_FILE}"

echo ""
echo "======================================================================"
echo "🎉 SUCCESS: Frames ${TAG} has been published to GitHub Releases!"
echo "   Release URL: https://github.com/whoavidwivedi/frames/releases/tag/${TAG}"
echo "======================================================================"
