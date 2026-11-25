#!/bin/bash
# Shared by the local build and the release workflow after signing.
set -euo pipefail
app="${1:?supply a signed frames.app}"
version="${2:?supply a version}"
out="${3:?supply an output directory}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]
plist="$app/Contents/Info.plist"
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$plist")" == "$version" ]]
[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$plist")" == whoavidwivedi.frames ]]
exe="$(/usr/bin/plutil -extract CFBundleExecutable raw "$plist")"
/usr/bin/lipo "$app/Contents/MacOS/$exe" -verify_arch arm64
/usr/bin/codesign --verify --deep --strict -R='identifier "whoavidwivedi.frames"' "$app"
mkdir -p "$out"
archive="Frames-v$version-macOS.zip"
ditto -c -k --keepParent "$app" "$out/$archive"
cp "$(dirname "$0")/install.sh" "$out/Frames-migrate.command"
chmod +x "$out/Frames-migrate.command"
(cd "$out" && shasum -a 256 "$archive" > SHA256SUMS.txt)
