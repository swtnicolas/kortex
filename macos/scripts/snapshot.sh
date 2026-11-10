#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
label=${1:?usage: scripts/snapshot.sh <label>}
out=build/measure
mkdir -p "$out"
pid=$(pgrep -x Kortex)

footprint -p "$pid" > "$out/$label.footprint" 2>/dev/null
vmmap --summary "$pid" > "$out/$label.vmmap" 2>/dev/null
vmmap -interleaved "$pid" > "$out/$label.regions" 2>/dev/null
heap -sortBySize "$pid" > "$out/$label.heap" 2>/dev/null
heap --addresses=all --noContent -q "$pid" > "$out/$label.addresses" 2>/dev/null
if [[ "${STACKS:-}" == 1 ]]; then
    malloc_history "$pid" -allBySize > "$out/$label.stacks" 2>/dev/null
fi
grep -E "^Physical footprint" "$out/$label.vmmap"
