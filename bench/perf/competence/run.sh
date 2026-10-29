#!/bin/sh
# usage: run.sh [repeats]; builds the competence kernels in Manuscript and Go and prints
# microseconds (min of N runs) and the ratio to Go per kernel; Rust is built at the usual release settings
# and again with overflow checks on. Checksums must match.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; GO=${GO:-go}; RUSTC=${RUSTC:-rustc}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO"); RUSTC=$(command -v "$RUSTC")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
case "$GO" in /*) ;; *) GO="$(pwd)/$GO";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/go" "$HERE/ms" "$HERE/rust" "$W/"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -o bench .)
mkdir -p "$W/rust-checked"
"$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rust/bench" "$W/rust/main.rs"
"$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -C overflow-checks=on -o "$W/rust-checked/bench" "$W/rust/main.rs"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
: > "$W/raw.txt"
versions='go ms rust rust-checked'
i=0
while [ "$i" -lt "$N" ]; do
  # Rotate the order each round so no version always runs first.
  order=$versions
  r=0
  while [ "$r" -lt "$i" ]; do order="${order#* } ${order%% *}"; r=$((r + 1)); done
  for v in $order; do
    "$W/$v/bench" > "$W/sample.txt"
    sed "s/^/$v /" "$W/sample.txt" >> "$W/raw.txt"
    printf '%s # end\n' "$v" >> "$W/raw.txt"
  done
  i=$((i + 1))
done
python3 "$HERE/../table.py" "$W/raw.txt" competence "$N" "$versions"
