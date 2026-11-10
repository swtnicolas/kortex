#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="$HOME/Applications/Kortex.app"
helper="/Library/PrivilegedHelperTools/local.kortex.fans"

"$root/scripts/build.sh"

pkill -x Kortex || true
mkdir -p "$HOME/Applications"
rm -rf "$target"
cp -R "$root/build/Kortex.app" "$target"
open "$target"

if [ -e "$helper" ] && ! cmp -s "$root/build/KortexFans" "$helper"; then
    echo "The installed fan helper differs from this build: run scripts/install-fans.sh" >&2
fi
