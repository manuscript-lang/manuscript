#!/bin/sh
# usage: run.sh [repeats]; plain element-wise list loops in GFLOPS (higher is better), best of N.
# ms is the Manuscript loops (`for i in 0..n: out[i] = ...`) built with `ms build`; c-sse2 and
# c-avx2 are the same loops in C at -O3 with strict IEEE semantics (no -ffast-math, no FMA
# contraction), so neither side may reorder floating-point reductions.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}; CC=${CC:-cc}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/ms" "$W/"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
"$CC" -O3 -ffp-contract=off "$HERE/c/kernels.c" -o "$W/c-sse2"
"$CC" -O3 -mavx2 -ffp-contract=off "$HERE/c/kernels.c" -o "$W/c-avx2"
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  "$W/ms/bench" | grep -v '^check' | sed 's/^/ms /' >> "$W/raw.txt"
  "$W/c-sse2" | grep -v '^check' | sed 's/^/c-sse2 /' >> "$W/raw.txt"
  "$W/c-avx2" | grep -v '^check' | sed 's/^/c-avx2 /' >> "$W/raw.txt"
  i=$((i + 1))
done
# Best GFLOPS per (kernel, version).
awk '{ k = $2 " " $1; if (!(k in best) || $3 > best[k]) best[k] = $3 } END { for (k in best) printf "%s %.2f\n", k, best[k] }' "$W/raw.txt" | sort
