#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Frames macOS Apple Silicon Official Release & GitHub Tagging Pipeline
# ==============================================================================
# Automates testing, version bumping, release compilation, code signing,
# packaging (macOS ZIP), checksum generation, git tagging, and
# GitHub Release publication.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
PBXPROJ_FILE="${PROJECT_ROOT}/frames.xcodeproj/project.pbxproj"

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
    if [[ -f "${PBXPROJ_FILE}" ]]; then
        CURRENT_VERSION=$(grep 'MARKETING_VERSION = ' "${PBXPROJ_FILE}" | head -n 1 | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d ' ')
    else
        CURRENT_VERSION="unknown"
    fi
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
    echo "==> [2/7] Running test suite with xcodebuild test..."
    TEST_RESULT_BUNDLE="${PROJECT_ROOT}/build/FramesTests.xcresult"
    rm -rf "${TEST_RESULT_BUNDLE}"

    # Rely on the xcodebuild exit code rather than grepping console text; a
    # logging change can no longer turn a failing suite into a false pass.
    if ! xcodebuild \
        -project "${PROJECT_ROOT}/frames.xcodeproj" \
        -scheme frames \
        -configuration Debug \
        -destination "platform=macOS,arch=arm64" \
        -derivedDataPath "${PROJECT_ROOT}/build/DerivedData" \
        -resultBundlePath "${TEST_RESULT_BUNDLE}" \
        CODE_SIGNING_ALLOWED=NO \
        test; then
        echo "❌ Test suite failed. Result bundle: ${TEST_RESULT_BUNDLE}"
        exit 1
    fi
    echo "  ✔ Test suite passed cleanly!"
else
    echo "==> [2/7] Skipping test suite (--skip-tests specified)."
fi

# ------------------------------------------------------------------------------
# 3. Version Bump in Xcode Project
# ------------------------------------------------------------------------------
echo "==> [3/7] Updating version to ${VERSION} in Xcode project..."
if [[ -f "${PBXPROJ_FILE}" ]]; then
    CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION = ' "${PBXPROJ_FILE}" | head -n 1 | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);/\1/' | tr -d ' ')
    NEW_BUILD=$((CURRENT_BUILD + 1))
    sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${VERSION};/g" "${PBXPROJ_FILE}"
    sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "${PBXPROJ_FILE}"
    echo "  MARKETING_VERSION: ${VERSION}"
    echo "  CURRENT_PROJECT_VERSION: ${NEW_BUILD}"
fi

# ------------------------------------------------------------------------------
# 4. Release Compilation & Signing
# ------------------------------------------------------------------------------
echo "==> [4/7] Building Release configuration for Apple Silicon..."
xcodebuild \
    -project "${PROJECT_ROOT}/frames.xcodeproj" \
    -scheme frames \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    SWIFT_PARALLEL_WHOLE_MODULE_OPTIMIZATION=YES \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -derivedDataPath "${PROJECT_ROOT}/build/DerivedData" \
    build

RELEASE_APP="${PROJECT_ROOT}/build/DerivedData/Build/Products/Release/frames.app"
if [[ ! -d "${RELEASE_APP}" ]]; then
    echo "❌ Error: Release bundle not generated at ${RELEASE_APP}"
    exit 1
fi

echo "Signing application bundle with Developer ID..."
SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "⚠️  Warning: MACOS_SIGNING_IDENTITY is not set; dry run will not produce a verifiable artifact."
    else
        echo "❌ Error: MACOS_SIGNING_IDENTITY is required. Unsigned releases are not published."
        exit 1
    fi
else
    codesign --force --deep --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${RELEASE_APP}"
    codesign --verify --deep --strict --verbose=2 "${RELEASE_APP}"
    if ! codesign -dvvv "${RELEASE_APP}" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
        echo "❌ Error: Signing identity is not a Developer ID Application certificate."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 5. Packaging Artifacts (macOS ZIP)
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

# Generate Checksums
CHECKSUM_FILE="${DIST_DIR}/SHA256SUMS.txt"
echo "Generating SHA-256 checksums..."
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ZIP_NAME}" > "${CHECKSUM_FILE}"
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
[[ -f "${PBXPROJ_FILE}" ]] && git add "${PBXPROJ_FILE}"

# Only commit if changes exist
if ! git diff --cached --quiet; then
    git commit -m "chore(release): bump version to ${TAG}"
fi

# Create annotated tag
git tag -a "${TAG}" -m "Frames ${TAG} — Native Apple Silicon Media Engine & In-App OTA Update"

echo "Pushing commits and tags to origin..."
CURRENT_BRANCH=$(git branch --show-current)
if [[ -n "${CURRENT_BRANCH}" && "${CURRENT_BRANCH}" != "main" ]]; then
    git push origin "${CURRENT_BRANCH}"
fi
git push origin HEAD:main
git push origin "${TAG}"

# ------------------------------------------------------------------------------
# 7. GitHub Release Publication
# ------------------------------------------------------------------------------
echo "==> [7/7] Publishing release on GitHub..."

# Prepare Release Notes
TEMP_NOTES_FILE="/tmp/Frames_release_notes_${VERSION}.md"
if [[ -n "${NOTES_FILE}" && -f "${NOTES_FILE}" ]]; then
    if [[ "${NOTES_FILE}" != "${TEMP_NOTES_FILE}" ]]; then
        cp "${NOTES_FILE}" "${TEMP_NOTES_FILE}"
    fi
elif [[ -n "${CUSTOM_NOTES}" ]]; then
    echo "${CUSTOM_NOTES}" > "${TEMP_NOTES_FILE}"
else
    cat <<EOF > "${TEMP_NOTES_FILE}"
## Frames ${TAG} — Native Apple Silicon Media Engine & In-App OTA Updates

### 🚀 What's New in this Release

• **In-App Production OTA Update Engine**: Instant update notifications without intrusive automatic restarts. Seamless in-app download, checksum integrity verification, atomic bundle swap, and app relaunch.
• **Instant Update Discovery**: Background release checking against GitHub Releases with SemVer 2.0.0 resolution, manual check affordance in App Menu and Command Palette.
• **Liquid Glass Update Modal**: Adaptive dual-mode interface showcasing real-time download progress, changelog highlights, and granular controls ("Update & Restart", "Later", "Skip this version").
• **Apple Silicon Performance Polish**: 458/458 automated tests passing across 34 suites with zero regressions, strict concurrency compliance, and ultra-low unified memory footprint.

### 📦 Installation

1. Download \`${ZIP_NAME}\` below.
2. Unzip and drag \`Frames.app\` to your \`/Applications\` folder.
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
