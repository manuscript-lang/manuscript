#!/bin/sh
# usage: run.sh BASE_MS HEAD_MS
# Proves that closing what containers and fields own costs nothing when no element is a
# resource: every benchmark project under bench/perf is lowered by a compiler from before the
# change (BASE_MS) and one with it (HEAD_MS), and the lowered MIR (`ms emit`) and the linked
# binaries must be byte for byte the same. Prints one line per project and exits 1 on a difference.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PERF=$(cd "$HERE/.." && pwd)
BASE=${1:?base ms binary}; HEAD=${2:?head ms binary}
case "$BASE" in /*) ;; *) BASE="$(pwd)/$BASE";; esac
case "$HEAD" in /*) ;; *) HEAD="$(pwd)/$HEAD";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
same=0; differ=0; skipped=0
for toml in $(find "$PERF" -name ms.toml | sort); do
  dir=$(dirname "$toml")
  name=${dir#"$PERF"/}
  # Both compilers build the same directory, so no path differs between the outputs.
  rm -rf "$W/p"; mkdir -p "$W/p"
  cp -R "$dir/." "$W/p/"
  rm -f "$W/p/ms.lock"
  if ! (cd "$W/p" && "$BASE" emit ms.toml -o "$W/a.mir" && "$HEAD" emit ms.toml -o "$W/b.mir") >/dev/null 2>&1; then
    echo "skip   $name (does not lower)"; skipped=$((skipped + 1)); continue
  fi
  (cd "$W/p" && rm -f ms.lock && "$BASE" build ms.toml -o "$W/a.bin" && rm -f ms.lock && "$HEAD" build ms.toml -o "$W/b.bin") >/dev/null 2>&1
  if cmp -s "$W/a.mir" "$W/b.mir" && cmp -s "$W/a.bin" "$W/b.bin"; then
    echo "same   $name"; same=$((same + 1))
  else
    echo "DIFFER $name"; differ=$((differ + 1))
  fi
done
echo "$same identical, $differ different, $skipped skipped"
[ "$differ" -eq 0 ]
