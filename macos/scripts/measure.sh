#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
tools=build/tools
out=build/measure
mkdir -p "$tools" "$out"
for tool in ax usage; do
    if [[ ! -x "$tools/$tool" || "tools/$tool.swift" -nt "$tools/$tool" ]]; then
        swiftc -O "tools/$tool.swift" -o "$tools/$tool"
    fi
done

app=${APP:-build/Kortex.app}
cycles=${CYCLES:-5}
hold=${OPEN:-5}
idle=${IDLE:-0}
tab=${TAB:-ram}
installed="$HOME/Applications/Kortex.app"

pkill -x Kortex || true
sleep 1
environment=()
for pair in "$@"; do environment+=(--env "$pair"); done
open -n -g ${environment[@]+"${environment[@]}"} "$app" --args -detailTab "$tab"
sleep 8
pid=$(pgrep -x Kortex)
echo "base      $("$tools/usage" "$pid")"
[[ "${SNAPSHOTS:-}" == 1 ]] && scripts/snapshot.sh base > /dev/null

for cycle in $(seq "$cycles"); do
    "$tools/usage" "$pid" --curve "$hold" > "$out/curve-$cycle.txt" &
    curve=$!
    "$tools/ax" open
    sleep "$hold"
    "$tools/ax" open
    wait "$curve"
    opened=$("$tools/usage" "$pid")
    [[ "${SNAPSHOTS:-}" == 1 && $cycle == 1 ]] && scripts/snapshot.sh open > /dev/null
    "$tools/ax" close
    sleep 4
    echo "cycle $cycle   open: $opened  $(tail -1 "$out/curve-$cycle.txt")  closed: $("$tools/usage" "$pid")"
    [[ "${SNAPSHOTS:-}" == 1 && $cycle == 1 ]] && scripts/snapshot.sh closed > /dev/null
done

if (( idle > 0 )); then
    echo "idle      $("$tools/usage" "$pid" "$idle")"
    [[ "${SNAPSHOTS:-}" == 1 ]] && scripts/snapshot.sh idle > /dev/null
fi

pkill -x Kortex || true
if [[ -d "$installed" ]]; then
    sleep 1
    open "$installed"
fi
