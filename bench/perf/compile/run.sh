#!/bin/sh
# usage: run.sh [repeats]; times `ms check`, Debug and Release builds of a generated ~30k-line,
# 31-module project (gen.py), and checks both executables print the same checksum.
# Compiler speed only: compare numbers from the same machine. MS names the compiler.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}; N=${1:-3}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
python3 "$HERE/gen.py" "$W/project"
cd "$W/project"
echo "lines $(cat src/*.ms | wc -l)"
now() { python3 -c 'import time; print(time.monotonic())'; }
# best-of-N wall seconds for the command
best() {
  name=$1; shift; min=
  i=0
  while [ "$i" -lt "$N" ]; do
    a=$(now); "$@" >/dev/null; b=$(now)
    min=$(python3 -c "d=$b-$a; m='$min'; print(min(d, float(m)) if m else d)")
    i=$((i + 1))
  done
  printf '%-8s %6.2fs\n' "$name" "$min"
}
best check "$MS" check ms.toml
best debug "$MS" build ms.toml --build-type Debug -o debug
best release "$MS" build ms.toml -o release
[ "$(./debug)" = "$(./release)" ] || { echo 'debug and release disagree' >&2; exit 1; }
