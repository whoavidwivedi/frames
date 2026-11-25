#!/bin/bash
# Package a reviewed version locally or ask GitHub to publish the same revision.
set -euo pipefail

usage() {
    cat <<'HELP'
Usage: scripts/release.sh VERSION [--dry-run] [--skip-tests] [--draft]
          [--prerelease] [--title TITLE] [--notes TEXT | --notes-file FILE]
--dry-run      Test, build and create the ad-hoc signed ZIP in dist/.
--skip-tests   Skip local tests (dry runs only). Publication always runs tests.
--draft        Create a draft GitHub release.
For publication, commit the version bump in the release PR and merge it first.
GitHub uses Developer ID credentials when configured, or ad-hoc signing when
the repository variable ALLOW_UNSIGNED_RELEASES=true.
HELP
}
fail() { echo "Release: $*" >&2; exit 1; }
version=""
dry_run=false
skip=false
draft=false
prerelease=false
title=""
notes=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run) dry_run=true ;;
        --skip-tests) skip=true ;;
        --draft) draft=true ;;
        --prerelease) prerelease=true ;;
        --title) shift; title="${1:?missing title}" ;;
        --notes) shift; notes="${1:?missing notes}" ;;
        --notes-file) shift; notes="$(cat "${1:?missing notes file}")" ;;
        *) [[ -z "$version" ]] || fail "Unknown argument $1"; version="${1#v}" ;;
    esac
    shift
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || fail "Supply a version such as 2.0.0."
cd "$(dirname "$0")/.."
project_version="$(awk '/MARKETING_VERSION = / {gsub(/;/, "", $3); print $3}' frames.xcodeproj/project.pbxproj | sort -u)"
[[ "$project_version" == "$version" ]] || fail "Project version ($project_version) must match $version."
if ! "$dry_run"; then
    if "$skip"; then fail "--skip-tests only applies to a local dry run."; fi
    [[ -z "$(git status --porcelain)" ]] || fail "Commit the reviewed release changes first."
    main_sha="$(git ls-remote --exit-code origin refs/heads/main | awk '{print $1}')"
    [[ "$(git rev-parse HEAD)" == "$main_sha" ]] || fail "The release must match the reviewed origin/main revision."
    gh workflow run release.yml --ref main -f version="$version" -f revision="$main_sha" \
        -f draft="$draft" -f prerelease="$prerelease" -f title="$title" -f notes="$notes"
    exit 0
fi

args=(-project frames.xcodeproj -scheme frames -destination "platform=macOS,arch=arm64"
      -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO)
if ! "$skip"; then xcodebuild "${args[@]}" -configuration Debug test; fi
xcodebuild "${args[@]}" -configuration Release build
app=build/DerivedData/Build/Products/Release/frames.app
codesign --force --sign - "$app"
scripts/package-release.sh "$app" "$version" dist
echo "Packaged Frames v$version in dist/."
