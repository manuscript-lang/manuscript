#!/bin/sh
# usage: run.sh [repeats]; compares whole kernels (list/record/Float/Int loops,
# recursive sum types, Int maps) with hand-written Go, min of N runs.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; GO=${GO:-$ROOT/toolchain/go/bin/go}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
case "$GO" in /*) ;; *) GO="$(pwd)/$GO";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/go" "$HERE/ms" "$W/"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -ldflags="-s -w -buildid=" -o bench .)
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  if [ $((i % 2)) -eq 0 ]; then versions='go ms'; else versions='ms go'; fi
  for v in $versions; do
    "$W/$v/bench" > "$W/sample.txt"
    sed "s/^/$v /" "$W/sample.txt" >> "$W/raw.txt"
  done
  i=$((i + 1))
done
python3 "$HERE/table.py" "$W/raw.txt"
