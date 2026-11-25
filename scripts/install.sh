#!/bin/bash
# Install the official Apple Silicon release using tools shipped with macOS.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: install.sh [--stable | --beta] [--dry-run] [--allow-adhoc] [--applications-dir=PATH]
  --applications-dir=PATH  Install in this Applications directory.
  --dry-run       Download and verify the release without installing or launching.
  --allow-adhoc   Consent to a release without Apple Developer ID or notarization.
  --beta          Prefer the most recent published prerelease.
HELP
}
fail() { echo "Frames installer: $*" >&2; exit 1; }

channel="${CHANNEL:-stable}"
applications_dir=""
dry_run=false
allow_adhoc=false
for arg in "$@"; do
    case "$arg" in
        --stable) channel=stable ;;
        --beta|--canary) channel=beta ;;
        --channel=*) channel="${arg#*=}" ;;
        --dry-run) dry_run=true ;;
        --applications-dir=/*) applications_dir="${arg#*=}" ;;
        --allow-adhoc) allow_adhoc=true ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $arg" ;;
    esac
done
case "$channel" in stable|beta|canary) ;; *) fail "Unknown channel: $channel" ;; esac
[[ "$(uname -s)" == Darwin ]] || fail "macOS is required."
if [[ "$(uname -m)" != arm64 && "$(sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]]; then
    fail "An Apple Silicon Mac is required."
fi

scratch="$(mktemp -d -t frames-install)"
stage=""
installed=""
backup=""
lock=""
cleanup() {
    local status=$?
    if [[ -n "$backup" && -d "$backup" && ! -e "$installed" ]]; then
        if ! mv "$backup" "$installed"; then
            echo "Previous installation retained at $backup" >&2
            stage=""
        fi
    fi
    [[ -z "$stage" ]] || rm -rf "$stage"
    [[ -z "$lock" ]] || rmdir "$lock" || true
    rm -rf "$scratch"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
repo=whoavidwivedi/frames
api="https://api.github.com/repos/$repo/releases"
curl_flags=(-fLsS --retry 2 --proto '=https' --proto-redir '=https')
headers=(-H 'Accept: application/vnd.github+json')
if [[ -n "${GITHUB_TOKEN:-}" ]]; then headers+=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
if [[ "$channel" == stable ]]; then
    curl "${curl_flags[@]}" "${headers[@]}" "$api/latest" -o "$scratch/release.json"
else
    curl "${curl_flags[@]}" "${headers[@]}" "$api?per_page=15" -o "$scratch/releases.json"
    /usr/bin/jq -e 'map(select(.draft != true)) | (map(select(.prerelease))[0] // .[0])' \
        "$scratch/releases.json" > "$scratch/release.json"
fi
tag="$(/usr/bin/jq -er '.tag_name' "$scratch/release.json")"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || fail "Invalid release tag."
archive="Frames-$tag-macOS.zip"
for name in "$archive" SHA256SUMS.txt; do
    url="https://github.com/$repo/releases/download/$tag/$name"
    /usr/bin/jq -e --arg name "$name" --arg url "$url" \
        'any(.assets[]; .name == $name and .browser_download_url == $url)' "$scratch/release.json" > /dev/null \
        || fail "Release $tag is missing $name."
    curl "${curl_flags[@]}" "$url" -o "$scratch/$name"
done
# Only the exact selected ZIP may satisfy this check. Ignore other release
# assets; never pass arbitrary filenames from the manifest to a local reader.
expected="$(awk -v file="$archive" 'NF == 2 && ($2 == file || $2 == "*" file) {print tolower($1)}' "$scratch/SHA256SUMS.txt")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "Missing or ambiguous SHA-256 for $archive."
actual="$(shasum -a 256 "$scratch/$archive")"
[[ "${actual%% *}" == "$expected" ]] || fail "The release archive failed SHA-256 verification."

ditto -xk "$scratch/$archive" "$scratch/extracted"
app="$scratch/extracted/frames.app"
[[ -d "$app" ]] || app="$scratch/extracted/Frames.app"
plist="$app/Contents/Info.plist"
[[ -d "$app" && ! -L "$app" && -f "$plist" ]] || fail "The archive is missing Frames.app."
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$plist")" == whoavidwivedi.frames ]] || fail "Incorrect bundle identifier."
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$plist")"
[[ "$version" == "${tag#v}" ]] || fail "Bundle version $version does not match release $tag."
codesign --verify --deep --strict -R='identifier "whoavidwivedi.frames"' "$app" || fail "The Frames code signature is invalid."
signature="$(codesign -dvvv "$app" 2>&1)"
team="${FRAMES_EXPECTED_TEAM_ID:-}"
if [[ -n "$team" && ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then fail "Invalid FRAMES_EXPECTED_TEAM_ID."; fi
if grep -qx 'Signature=adhoc' <<< "$signature"; then
    [[ -z "$team" ]] || fail "This build cannot satisfy the configured Developer ID team."
    adhoc=true
else
    requirement='anchor apple generic and identifier "whoavidwivedi.frames" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
    if [[ -n "$team" ]]; then requirement+=" and certificate leaf[subject.OU] = \"$team\""; fi
    codesign --verify --deep --strict -R="$requirement" "$app" || fail "Invalid Developer ID signature."
    adhoc=false
fi
echo "Verified Frames $version ($archive)."
if "$dry_run"; then exit 0; fi

# Prefer an existing installation, or the user Applications folder on Macs
# where this account cannot write to /Applications. Never request sudo.
parent=/Applications
if [[ -n "$applications_dir" ]]; then
    parent="$applications_dir"
    mkdir -p "$parent"
elif [[ ! -e "$parent/Frames.app" && ( -d "$HOME/Applications/Frames.app" || ! -w "$parent" ) ]]; then
    parent="$HOME/Applications"
    mkdir -p "$parent"
fi
installed="$parent/Frames.app"
[[ -w "$parent" ]] || fail "Move Frames to a writable Applications folder and retry."
mkdir "$parent/.frames-install.lock" 2>/dev/null || fail "Another installation is active or the Applications folder is read-only."
lock="$parent/.frames-install.lock"
if [[ -e "$installed" || -L "$installed" ]]; then
    [[ -d "$installed" && ! -L "$installed" && "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$installed/Contents/Info.plist")" == whoavidwivedi.frames ]] \
        || fail "The existing destination is not a Frames installation."
    if "$adhoc" && codesign -dvvv "$installed" 2>&1 | grep '^Authority=' > /dev/null; then
        fail "A Developer ID installation requires a signed update."
    fi
    if pgrep -ix frames > /dev/null; then fail "Quit Frames and run the installer again."; fi
fi
if "$adhoc" && ! "$allow_adhoc"; then
    echo "This release is ad-hoc signed. Apple has not verified its publisher or notarized the app."
    if ! { read -r -p "Install this Frames GitHub release? [y/N] " answer < /dev/tty; } 2>/dev/null; then
        fail "Use --allow-adhoc to explicitly accept this build in a noninteractive session."
    fi
    [[ "$answer" == y || "$answer" == Y ]] || fail "Installation cancelled."
fi

# Finish copying on the destination volume before moving the existing app.
stage="$(mktemp -d "$parent/.frames-install.XXXXXXXX")"
ditto "$app" "$stage/Frames.app"
codesign --verify --deep --strict "$stage/Frames.app"
if [[ -e "$installed" ]]; then
    backup="$stage/previous.app"
    mv "$installed" "$backup"
fi
mv "$stage/Frames.app" "$installed"
echo "Installed $installed."
if "$adhoc"; then
    echo "If macOS blocks the first launch, use System Settings > Privacy & Security > Open Anyway for Frames."
fi
open "$installed" || echo "Open Frames from Finder to finish first launch." >&2
