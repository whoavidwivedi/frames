#!/bin/bash
# Exercise the production scripts using a real signed fixture and offline assets.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(mktemp -d -t frames-install-test)"
trap 'rm -rf "$root"' EXIT
export FRAMES_TEST_ROOT="$root"
app="$root/frames.app"
mkdir -p "$app/Contents/MacOS" "$root/bin" "$root/Applications"
echo 'int main(void) { return 0; }' | /usr/bin/clang -x c - -o "$app/Contents/MacOS/frames"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>frames</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIdentifier</key><string>whoavidwivedi.frames</string>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
scripts/package-release.sh "$app" 2.0.0 "$root/dist"
archive=Frames-v2.0.0-macOS.zip
base_url=https://github.com/whoavidwivedi/frames/releases/download/v2.0.0
/usr/bin/jq -n --arg archive "$archive" --arg base "$base_url" \
    '{tag_name:"v2.0.0", assets:([$archive,"SHA256SUMS.txt"] | map({name:.,browser_download_url:($base+"/"+.)}))}' > "$root/latest"
cat > "$root/bin/curl" <<'CURL'
#!/bin/bash
set -eu
while [[ $# -gt 0 ]]; do
    case "$1" in
        https://api.github.com/*/releases/latest) input="$FRAMES_TEST_ROOT/latest" ;;
        https://github.com/*/releases/download/*) input="$FRAMES_TEST_ROOT/dist/${1##*/}" ;;
        -o) shift; output="$1" ;;
    esac
    shift
done
cp "$input" "$output"
CURL
cat > "$root/bin/mv" <<'MV'
#!/bin/bash
if [[ "${FRAMES_TEST_FAIL_SWAP:-}" == 1 && "$1" == */.frames-install.*/Frames.app ]]; then exit 1; fi
exec /bin/mv "$@"
MV
printf '#!/bin/bash\nexit 0\n' > "$root/bin/open"
printf '#!/bin/bash\nexit 1\n' > "$root/bin/pgrep"
chmod +x "$root"/bin/*
export PATH="$root/bin:$PATH"
scripts/migrate.command --dry-run
args=(--allow-adhoc "--applications-dir=$root/Applications")
scripts/install.sh "${args[@]}"
installed="$root/Applications/Frames.app"
codesign --verify --deep --strict "$installed"

# Inode identity proves that rollback actually restored the previous directory.
inode="$(stat -f %i "$installed")"
if FRAMES_TEST_FAIL_SWAP=1 scripts/install.sh "${args[@]}"; then exit 1; fi
[[ "$(stat -f %i "$installed")" == "$inode" ]]
if FRAMES_EXPECTED_TEAM_ID=ABCDE12345 scripts/install.sh "${args[@]}"; then exit 1; fi
scripts/install.sh "${args[@]}"
codesign --verify --deep --strict "$installed"
inode="$(stat -f %i "$installed")"
mv "$root/dist/SHA256SUMS.txt" "$root/valid-manifest"
echo 'unrelated  OtherAsset.zip' > "$root/dist/SHA256SUMS.txt"
if scripts/install.sh "${args[@]}"; then exit 1; fi
cp "$root/valid-manifest" "$root/dist/SHA256SUMS.txt"
echo corruption >> "$root/dist/$archive"
if scripts/install.sh "${args[@]}"; then exit 1; fi
[[ "$(stat -f %i "$installed")" == "$inode" ]]
echo "Passed installer verification, upgrade, rollback, and checksum checks."
