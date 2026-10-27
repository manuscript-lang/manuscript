#!/bin/sh
# usage: run.sh [repeats]; fp32 matrix-vector products in GFLOPS (higher is better), best of N runs.
# ms-vec is @std/vec.ms Matrix.matvec with the CPU's best kernel copy; ms-vec-baseline forces the
# baseline copy (MS_VEC_LEVEL=baseline); ms-scalar is the same product as a plain Manuscript loop.
# The C builds use -O3: c-scalar keeps IEEE order, c-lanes is the same 8-lane four-accumulator
# kernel as @std/vec.ms (c-lanes-sse2 without AVX), and c-fastmath lets the compiler reorder.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
MS=${MS:-$ROOT/target/release/ms}; CC=${CC:-cc}; N=${1:-5}
case "$N" in ''|*[!0-9]*|0) echo 'repeats must be a positive integer' >&2; exit 2;; esac
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT HUP INT TERM
cp -r "$HERE/ms" "$W/"
(cd "$W/ms" && rm -f ms.lock && "$MS" build ms.toml -o bench >&2)
"$CC" -O3 -DKERNEL_scalar "$HERE/c/matvec.c" -o "$W/c-scalar"
"$CC" -O3 -Wno-psabi -DKERNEL_lanes "$HERE/c/matvec.c" -o "$W/c-lanes-sse2"
"$CC" -O3 -mavx2 -mfma -DKERNEL_lanes "$HERE/c/matvec.c" -o "$W/c-lanes"
"$CC" -O3 -march=native -ffast-math -DKERNEL_fast "$HERE/c/matvec.c" -o "$W/c-fastmath"
: > "$W/raw.txt"
i=0
while [ "$i" -lt "$N" ]; do
  "$W/ms/bench" | sed 's/^vec /ms-vec /; s/^scalar /ms-scalar /' >> "$W/raw.txt"
  MS_VEC_LEVEL=baseline "$W/ms/bench" | grep '^vec ' | sed 's/^vec /ms-vec-baseline /' >> "$W/raw.txt"
  for c in c-scalar c-lanes-sse2 c-lanes c-fastmath; do "$W/$c" "$c" >> "$W/raw.txt"; done
  i=$((i + 1))
done
# Best GFLOPS per (version, size).
awk '{ k = $1 " " $2; if (!(k in best) || $3 > best[k]) best[k] = $3 } END { for (k in best) printf "%s %.2f\n", k, best[k] }' "$W/raw.txt" | sort
