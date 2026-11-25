#!/bin/bash
set -euo pipefail

# Older in-app updaters require a Developer ID signature. The .command
# release asset contains the installer itself. Keep the legacy source URL
# functional for users following installation notes from earlier versions.
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$here/install.sh" ]]; then exec /bin/bash "$here/install.sh" "$@"; fi
fi
installer="$(mktemp -t frames-installer)"
trap 'rm -f "$installer"' EXIT
/usr/bin/curl -fsSL --proto '=https' --proto-redir '=https' \
    https://raw.githubusercontent.com/whoavidwivedi/frames/main/scripts/install.sh -o "$installer"
/bin/bash "$installer" "$@"
