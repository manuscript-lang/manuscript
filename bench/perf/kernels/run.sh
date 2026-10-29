#!/bin/sh
# usage: run.sh [repeats]; compares whole kernels (list/record/Float/Int loops,
# recursive sum types, Int maps) with hand-written Go and C, min of N runs.
# c-ms is the C a no-GC Manuscript backend would emit; ABLATE=1 adds c-ms builds
# with one runtime check removed each, to attribute its cost.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/ms}; GO=${GO:-$ROOT/toolchain/go/bin/go}; CC=${CC:-cc}; RUSTC=${RUSTC:-rustc}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
MS=$(command -v "$MS"); GO=$(command -v "$GO"); CC=$(command -v "$CC"); RUSTC=$(command -v "$RUSTC")
case "$MS" in /*) ;; *) MS="$(pwd)/$MS";; esac
case "$GO" in /*) ;; *) GO="$(pwd)/$GO";; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/go" "$HERE/ms" "$HERE/rust" "$W/"
(cd "$W/go" && CGO_ENABLED=0 "$GO" build -buildvcs=false -trimpath -ldflags="-s -w -buildid=" -o bench .)
mkdir -p "$W/rust-checked"
"$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -o "$W/rust/bench" "$W/rust/main.rs"
"$RUSTC" --edition 2021 -C opt-level=3 -C codegen-units=1 -C overflow-checks=on -o "$W/rust-checked/bench" "$W/rust/main.rs"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
CFLAGS="-O2 -std=c11 -ffp-contract=off"
cc_build_named() { name=$1; src=$2; shift 2; mkdir -p "$W/$name" && "$CC" $CFLAGS "$@" "$src" -o "$W/$name/bench"; }
cc_build_named c "$HERE/c/plain.c"
cc_build_named c-ms "$HERE/c/ms.c"
versions='go ms rust rust-checked c c-ms'
if [ "${ABLATE:-0}" = 1 ]; then
  cc_build_named c-ms-no-poll "$HERE/c/ms.c" -DMS_NO_POLL
  cc_build_named c-ms-no-overflow "$HERE/c/ms.c" -DMS_NO_OVERFLOW
  cc_build_named c-ms-no-bounds "$HERE/c/ms.c" -DMS_NO_BOUNDS
  cc_build_named c-ms-unchecked "$HERE/c/ms.c" -DMS_NO_POLL -DMS_NO_OVERFLOW -DMS_NO_BOUNDS
  versions="$versions c-ms-no-poll c-ms-no-overflow c-ms-no-bounds c-ms-unchecked"
fi
: > "$W/raw.txt"
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
python3 "$HERE/../table.py" "$W/raw.txt" kernels "$N" "$versions"
