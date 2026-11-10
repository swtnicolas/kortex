#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$root/build/Kortex.app"
helper="$root/build/KortexFans"

swift build --package-path "$root" --configuration release

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$root/.build/release/Kortex" "$bundle/Contents/MacOS/Kortex"
cp "$root/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$root/assets/icon/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$bundle"

cp "$root/.build/release/KortexFans" "$helper"
codesign --force --sign - --identifier local.kortex.fans --options runtime "$helper"

echo "$bundle"
