#!/bin/sh
# usage: run.sh [repeats]; compares StringBuilder.append against Rust's String::push_str for pieces of 4 B to 8 KiB,
# (microseconds to build about 1 MB) and List[Int].append against Vec::push for 10K to 1M items, min of N runs.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; RUSTC=${RUSTC:-rustc}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
EXE=
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=.exe ;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/ms" "$W/"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o "bench$EXE" >&2)
# RUSTC_LINKER names the linker when PATH has the wrong one (Git's `link` shadows MSVC's on Windows runners).
if [ -n "${RUSTC_LINKER:-}" ]; then
  "$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -C linker="$RUSTC_LINKER" -o "$W/rust$EXE" "$HERE/rust/main.rs"
else
  "$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rust$EXE" "$HERE/rust/main.rs"
fi
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  for v in ms rust; do
    if [ "$v" = ms ]; then "$W/ms/bench$EXE" > "$W/sample.txt"; else "$W/rust$EXE" > "$W/sample.txt"; fi
    awk -v i="$i" -v v="$v" '{print i "\t" v "\t" $0}' "$W/sample.txt" >> "$W/raw.txt"
  done
  i=$((i + 1))
done
python3 "$HERE/table.py" "$W/raw.txt" "$N"
