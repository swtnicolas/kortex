#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target="/Library/PrivilegedHelperTools/local.kortex.fans"

"$root/scripts/build.sh" > /dev/null
sudo install -o root -g admin -m 4750 "$root/build/KortexFans" "$target"
ls -l "$target"
